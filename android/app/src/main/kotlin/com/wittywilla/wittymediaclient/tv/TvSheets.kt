package com.wittywilla.wittymediaclient.tv

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.wittywilla.wittymediaclient.net.GuideCell
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideHit
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.GuideRules
import com.wittywilla.wittymediaclient.net.TvLook
import com.wittywilla.wittymediaclient.net.TvLookChoice
import com.wittywilla.wittymediaclient.net.TvSaved
import com.wittywilla.wittymediaclient.net.TvShape
import com.wittywilla.wittymediaclient.net.TvTheme
import com.wittywilla.wittymediaclient.net.guideDay
import com.wittywilla.wittymediaclient.net.problemText
import com.wittywilla.wittymediaclient.net.searchGuide
import com.wittywilla.wittymediaclient.ui.FieldKind
import com.wittywilla.wittymediaclient.ui.LocalExtraColours
import com.wittywilla.wittymediaclient.ui.LocalMetrics
import com.wittywilla.wittymediaclient.ui.Nav
import com.wittywilla.wittymediaclient.ui.Pressable
import com.wittywilla.wittymediaclient.ui.Radius
import com.wittywilla.wittymediaclient.ui.Route
import com.wittywilla.wittymediaclient.ui.Spinner
import com.wittywilla.wittymediaclient.ui.WittyField
import com.wittywilla.wittymediaclient.ui.caption
import com.wittywilla.wittymediaclient.ui.corner
import com.wittywilla.wittymediaclient.ui.label
import com.wittywilla.wittymediaclient.ui.secondary
import com.wittywilla.wittymediaclient.ui.section
import com.wittywilla.wittymediaclient.ui.title
import com.wittywilla.wittymediaclient.ui.u
import com.wittywilla.wittymediaclient.ui.body
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

// What opens over the guide: more about a programme or the channel's whole day, searching the schedule, and the Look
// panel. As on the server's page (Details.tsx, SearchPanel.tsx and LookPanel.tsx) and Apple TV's sheets, these are in
// the app's own colours, whichever look the guide has.

// A sheet over what's below, as tvOS draws one: what's below dims by half, and a card in the app's background colour, as
// wide as what's in it up to 1760, comes up in the middle; a tall one starts 60 from the top and runs off the bottom.
// Back closes it, and focus stays in it.
@Composable
fun TvSheet(onClose: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val scheme = MaterialTheme.colorScheme
    TvLayer(onClose) {
        Layout(
            content = {
                Column(
                    Modifier
                        .widthIn(max = (1760 * TV_UNIT).dp)
                        .clip(RoundedCornerShape((64 * TV_UNIT).dp))
                        .background(scheme.background)
                        .verticalScroll(rememberScrollState()),
                    content = content,
                )
            },
            modifier = Modifier.fillMaxSize(),
        ) { measurables, constraints ->
            val top = (60 * TV_UNIT).dp.roundToPx()
            val card = measurables[0].measure(constraints.copy(minWidth = 0, minHeight = 0, maxHeight = constraints.maxHeight - top + (66 * TV_UNIT).dp.roundToPx()))
            layout(constraints.maxWidth, constraints.maxHeight) {
                val y = if (card.height >= constraints.maxHeight - top * 2) top else (constraints.maxHeight - card.height) / 2
                card.place((constraints.maxWidth - card.width) / 2, y)
            }
        }
    }
}

// A layer of its own over the screen: its own window, so the remote stays in it, with what's below dimmed by half.
@Composable
fun TvLayer(onClose: () -> Unit, content: @Composable () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        val window = (LocalView.current.parent as? DialogWindowProvider)?.window
        LaunchedEffect(window) {
            window?.setDimAmount(0f)
            window?.setLayout(android.view.ViewGroup.LayoutParams.MATCH_PARENT, android.view.ViewGroup.LayoutParams.MATCH_PARENT)
        }
        Box(Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f))) { content() }
    }
}

// `preferred` is the one focus starts on, as an alert's default action; else the cancel one.
class TvDialogButton(val words: String, val destructive: Boolean = false, val cancel: Boolean = false, val preferred: Boolean = false, val action: () -> Unit)

// An alert, as tvOS draws one: a dark card 584 wide in the middle, its title and message, and its buttons side by side
// (or one under another, for a list to choose from), the cancel one focused first. Focused, a button fills white.
@Composable
fun TvDialog(title: String, message: String?, buttons: List<TvDialogButton>, onClose: () -> Unit, stacked: Boolean = false) {
    TvLayer(onClose) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(
                Modifier
                    .width((584 * TV_UNIT).dp)
                    .clip(RoundedCornerShape((50 * TV_UNIT).dp))
                    .background(Color(0xF21D1F23))
                    .border((1 * TV_UNIT).dp, Color.White.copy(alpha = 0.08f), RoundedCornerShape((50 * TV_UNIT).dp))
                    .padding(start = (30 * TV_UNIT).dp, end = (30 * TV_UNIT).dp, top = ((if (title.isEmpty()) 30 else 44) * TV_UNIT).dp, bottom = (30 * TV_UNIT).dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                var lines by remember { mutableIntStateOf(1) }
                if (title.isNotEmpty()) Text(
                    title, color = Color.White, style = MaterialTheme.typography.body.copy(fontSize = tvSp(33f), fontWeight = FontWeight.SemiBold),
                    textAlign = if (lines > 1) TextAlign.Start else TextAlign.Center, onTextLayout = { lines = it.lineCount },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = (16 * TV_UNIT).dp).semantics { heading() },
                )
                if (!message.isNullOrEmpty()) {
                    Text(
                        message, color = Color.White.copy(alpha = 0.6f), style = MaterialTheme.typography.body.copy(fontSize = tvSp(27f)), textAlign = TextAlign.Center,
                        modifier = Modifier.padding(top = (12 * TV_UNIT).dp),
                    )
                }
                if (title.isNotEmpty() || !message.isNullOrEmpty()) Spacer(Modifier.height((32 * TV_UNIT).dp))
                val first = buttons.indexOfFirst { it.preferred }.takeIf { it >= 0 } ?: buttons.indexOfFirst { it.cancel }.coerceAtLeast(0)
                if (stacked) {
                    Column(
                        Modifier.fillMaxWidth().weight(1f, fill = false).verticalScroll(rememberScrollState()).focusGroup(),
                        verticalArrangement = Arrangement.spacedBy((16 * TV_UNIT).dp),
                    ) {
                        buttons.forEachIndexed { i, b -> DialogButton(b, i == 0, Modifier.fillMaxWidth()) }
                    }
                } else {
                    Row(Modifier.fillMaxWidth().focusGroup(), horizontalArrangement = Arrangement.spacedBy((21 * TV_UNIT).dp)) {
                        buttons.forEachIndexed { i, b -> DialogButton(b, i == first, Modifier.weight(1f)) }
                    }
                }
            }
        }
    }
}

@Composable
private fun DialogButton(b: TvDialogButton, first: Boolean, modifier: Modifier) {
    val red = Color(0xFFFF453A)
    Pressable(b.action, modifier, shape = Radius.FULL, ring = false, takeFocus = first, label = b.words) { active ->
        Box(
            Modifier
                .fillMaxWidth()
                .defaultMinSize(minHeight = (66 * TV_UNIT).dp)
                .background(if (active) Color.White else if (b.destructive) red.copy(alpha = 0.18f) else Color(0xFF28292D), Radius.FULL)
                .padding(horizontal = (20 * TV_UNIT).dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                b.words, color = if (b.destructive) red else if (active) Color.Black else Color.White, maxLines = 1, overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.body.copy(fontSize = tvSp(31f), fontWeight = FontWeight.Medium),
            )
        }
    }
}

// Type at a size in TV units, whatever the device's own text size.
@Composable
fun tvSp(points: Float) = with(androidx.compose.ui.platform.LocalDensity.current) { (points * TV_UNIT).dp.toSp() }

enum class SheetKind { Primary, Secondary, Quiet }

// The app's own button on a TV, as Apple TV's `.action()`: a pill 66 high (a quiet one 56), `selected` marking the
// chosen one of a set in `border`.
@Composable
fun SheetButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: SheetKind = SheetKind.Secondary,
    selected: Boolean = false,
    icon: ImageVector? = null,
    takeFocus: Boolean = false,
) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val fill = when (kind) {
        SheetKind.Primary -> scheme.primary
        SheetKind.Quiet -> Color.Transparent
        SheetKind.Secondary -> if (selected) scheme.outline else scheme.surfaceVariant
    }
    val ink = when (kind) {
        SheetKind.Primary -> scheme.onPrimary
        SheetKind.Quiet -> extra.accentText
        SheetKind.Secondary -> scheme.onBackground
    }
    Pressable(onClick, modifier, shape = Radius.FULL, fill = fill, selected = selected, state = if (selected) "Selected" else null, takeFocus = takeFocus) {
        Row(
            Modifier
                .defaultMinSize(minHeight = metrics.u(if (kind == SheetKind.Quiet) 56 else 66))
                .padding(horizontal = metrics.u(if (kind == SheetKind.Quiet) 16 else 32), vertical = metrics.u(8)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(8)),
        ) {
            if (icon != null) Icon(icon, contentDescription = null, tint = ink, modifier = Modifier.size(metrics.u(30)))
            Text(
                text, color = ink, textAlign = TextAlign.Center,
                style = MaterialTheme.typography.label.let { if (kind == SheetKind.Quiet) it.copy(fontWeight = FontWeight.SemiBold) else it },
            )
        }
    }
}

// Inside a sheet: the gutter at the sides and the edge above and below, as Apple TV's sheets have.
@Composable
private fun SheetPage(maxWidth: Dp? = null, content: @Composable ColumnScope.() -> Unit) {
    val metrics = LocalMetrics.current
    Column(
        Modifier
            .then(if (maxWidth != null) Modifier.widthIn(max = maxWidth) else Modifier.fillMaxWidth())
            .padding(horizontal = metrics.gutter, vertical = metrics.edge),
        verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
        content = content,
    )
}

// More about a programme, or the whole of the channel's day: one sheet, so one is a press from the other.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun GuideDetails(
    nav: Nav,
    ask: GuideAsk,
    now: Long,
    onWatch: (String) -> Unit,
    onSaid: (String) -> Unit,
    onRecord: (GuideChannel, GuideProgramme) -> Unit,
    onSeries: (GuideChannel, GuideProgramme) -> Unit,
    onClose: () -> Unit,
) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val channel = ask.channel
    val p = ask.programme
    var day by remember { mutableStateOf(ask.day) }
    var desc by remember { mutableStateOf(p?.desc.orEmpty()) }
    var list by remember { mutableStateOf<List<GuideProgramme>?>(null) }
    var error by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        val id = p?.itemId
        if (desc.isEmpty() && id != null) runCatching { api.item(id) }.getOrNull()?.let { desc = it.overview }
    }
    LaunchedEffect(day) {
        if (!day || list != null) return@LaunchedEffect
        val start = GuideRules.startOfDay(ask.cell.start)
        try {
            list = api.guideDay(channel.key, maxOf(start, now - 86000))
            error = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            error = problemText(e, "The day couldn't be loaded.")
        }
    }
    TvSheet(onClose) {
        SheetPage(maxWidth = metrics.u(1300)) {
            Text(
                if (day) "Channel ${channel.number}, ${channel.name}" else p?.title ?: ask.cell.title,
                style = MaterialTheme.typography.title, color = scheme.onBackground, modifier = Modifier.semantics { heading() },
            )
            Row(Modifier.focusGroup(), horizontalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                SheetButton("This programme", { day = false }, selected = !day)
                SheetButton("The whole day", { day = true }, selected = day)
            }
            if (day) DayList(channel, list, error, now, onSaid) else OneProgramme(channel, ask, p, desc)
            val later = ask.cell.start > now
            val reminded = p != null && TvReminders.has(channel.key, p.start)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(16)), verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                if (channel.canTune) {
                    SheetButton("Watch channel now", { onWatch(channel.key) }, kind = if (channel.alternative == null) SheetKind.Primary else SheetKind.Secondary, icon = TvSymbols.Play, takeFocus = true)
                }
                channel.alternative?.let { alt -> SheetButton("Watch ${alt.number} ${alt.name} instead", { onWatch(alt.key) }, kind = SheetKind.Primary, icon = TvSymbols.Play) }
                if (later && channel.canTune && ask.cell.kind == GuideCell.Kind.Programme && p != null) {
                    SheetButton(if (reminded) "✓ Reminder set" else "Remind me", { scope.launch { onSaid(TvReminders.toggle(channel.key, p)) } }, selected = reminded)
                }
                if (channel.canRecord == true && ask.cell.isBroadcast && ask.cell.end > now && p != null) {
                    SheetButton("Record every airing", { onSeries(channel, p); onClose() })
                    SheetButton("Record this", { onRecord(channel, p); onClose() })
                }
                if (nav.me?.isAdmin == true && channel.kind == "library") {
                    SheetButton("Edit channel", { onClose(); nav.push(Route.OnPhone("Edit channel", "/tv/channels")) }, kind = SheetKind.Quiet)
                }
                SheetButton("Close", onClose, kind = SheetKind.Quiet, takeFocus = !channel.canTune)
            }
        }
    }
}

@Composable
private fun OneProgramme(channel: GuideChannel, ask: GuideAsk, p: GuideProgramme?, desc: String) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val body = MaterialTheme.typography.body
    val quiet = scheme.onSurfaceVariant
    Column(verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        p?.sub?.takeIf { it.isNotEmpty() }?.let { Text(it, style = body, color = quiet) }
        Text(
            "Channel ${channel.number}, ${channel.name}" +
                (if (ask.cell.kind == GuideCell.Kind.None) "" else " · ${GuideRules.dayName(ask.cell.start)}, ${GuideRules.span(ask.cell.start, ask.cell.end)}") +
                (p?.rating?.let { " · $it" } ?: ""),
            style = body, color = quiet,
        )
        if (ask.cell.kind == GuideCell.Kind.Group) {
            for (x in ask.cell.group) Text("${tvClock(x.start)}  ${x.title}" + (x.sub?.let { " $it" } ?: ""), style = body, color = scheme.onBackground)
        }
        if (desc.isNotEmpty()) Text(desc, style = body, color = scheme.onBackground)
        val s = channel.security
        if (s?.state == "encrypted") {
            Text(buildAnnotatedString { withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(s.label + ". ") }; append(s.detail) }, style = body, color = scheme.onBackground)
        }
        if (s?.state == "unknown") Text(s.detail, style = MaterialTheme.typography.secondary, color = quiet)
        channel.noRecord?.takeIf { it.isNotEmpty() }?.let { Text("This channel can't be recorded: $it.", style = MaterialTheme.typography.secondary, color = quiet) }
        channel.notices.orEmpty().forEach { Text(it, style = MaterialTheme.typography.secondary, color = quiet) }
        // Only ever an explanation: whether Record is offered is the server's canRecord alone.
        if (channel.canRecord != true && channel.kind == "library") {
            Text("Library channels can't be recorded: what they play is already in your library.", style = MaterialTheme.typography.secondary, color = quiet)
        }
    }
}

@Composable
private fun DayList(channel: GuideChannel, list: List<GuideProgramme>?, error: String, now: Long, onSaid: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val body = MaterialTheme.typography.body
    when {
        error.isNotEmpty() -> Text(error, style = body, color = scheme.error)
        list == null -> Box(Modifier.fillMaxWidth().height(metrics.u(120)), contentAlignment = Alignment.Center) { Spinner(scheme.onBackground, metrics.u(48)) }
        else -> Column(verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
            if (list.isEmpty()) Text("Nothing is listed for this day.", style = body, color = scheme.onSurfaceVariant)
            for (x in list) {
                val on = x.isOn(now)
                Row(
                    Modifier
                        .fillMaxWidth()
                        .graphicsLayer { alpha = if (x.end <= now) 0.6f else 1f }
                        .background(if (on) scheme.primary.copy(alpha = 0.16f) else Color.Transparent)
                        .padding(horizontal = metrics.u(8))
                        .focusGroup(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(metrics.u(16)),
                ) {
                    Text(tvClock(x.start), style = body.copy(fontFeatureSettings = "tnum"), color = scheme.onSurfaceVariant, modifier = Modifier.width(metrics.u(150)))
                    Text(
                        buildAnnotatedString {
                            withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(x.title) }
                            x.sub?.let { withStyle(SpanStyle(color = scheme.onSurfaceVariant)) { append(" $it") } }
                            if (on) withStyle(SpanStyle(color = extra.accentText)) { append("  On now") }
                        },
                        style = body, color = scheme.onBackground, modifier = Modifier.weight(1f),
                    )
                    if (x.start > now && x.kind != "slate" && channel.canTune) {
                        val set = TvReminders.has(channel.key, x.start)
                        SheetButton(if (set) "✓ Reminder set" else "Remind", { scope.launch { onSaid(TvReminders.toggle(channel.key, x)) } }, selected = set)
                    }
                }
            }
        }
    }
}

// Searching what's coming up, by title.
@Composable
fun GuideSearch(nav: Nav, onGo: (GuideHit) -> Unit, onClose: () -> Unit) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    var words by remember { mutableStateOf("") }
    var hits by remember { mutableStateOf<List<GuideHit>?>(null) }
    var error by remember { mutableStateOf("") }
    fun search() {
        scope.launch {
            try {
                hits = api.searchGuide(words)
                error = ""
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemText(e, "The schedule couldn't be searched.")
            }
        }
    }
    TvSheet(onClose) {
        SheetPage(maxWidth = metrics.u(1300)) {
            Text("Search the schedule", style = MaterialTheme.typography.title, color = scheme.onBackground, modifier = Modifier.semantics { heading() })
            WittyField(words, { words = it }, "A programme's name", kind = FieldKind.Text, imeAction = ImeAction.Search, onAction = ::search)
            if (error.isNotEmpty()) Text(error, style = MaterialTheme.typography.body, color = scheme.error)
            hits?.let { found ->
                if (found.isEmpty()) Text("Nothing coming up matches that.", style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant)
                for (hit in found) {
                    Pressable({ onGo(hit) }, Modifier.fillMaxWidth(), shape = metrics.corner(10), fill = scheme.surfaceVariant) {
                        Column(Modifier.fillMaxWidth().padding(metrics.u(12)), verticalArrangement = Arrangement.spacedBy(metrics.u(2))) {
                            Text(hit.title, style = MaterialTheme.typography.label, color = scheme.onBackground)
                            Text(
                                "${GuideRules.dayName(hit.start)}, ${GuideRules.span(hit.start, hit.end)} · ${hit.number.orEmpty()} ${hit.name.orEmpty()}",
                                style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            SheetButton("Close", onClose, kind = SheetKind.Quiet)
        }
    }
}

// WittyTV's look: one big choice, the theme, each drawn as a small picture of itself, then the rest. Everything shows at
// once and is kept with the account, as on the page.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TvLookPanel(nav: Nav, onClose: () -> Unit) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val look = TvLookStore.look
    val app = tvAppColours(scheme, LocalExtraColours.current)
    fun change(key: String, value: Any?) = TvLookStore.change(key, value, api)
    TvSheet(onClose) {
        SheetPage {
            Column(verticalArrangement = Arrangement.spacedBy(metrics.u(24))) {
                Text("Look", style = MaterialTheme.typography.title, color = scheme.onBackground, modifier = Modifier.semantics { heading() })
                Text(
                    when (look.source) {
                        TvLookChoice.Source.You -> "You chose this. It's kept with your account, on every device."
                        TvLookChoice.Source.App -> "The app's theme suggests this one, until you choose."
                        TvLookChoice.Source.Owner -> "This server's owner starts everyone on this one, until you choose."
                    },
                    style = MaterialTheme.typography.body, color = scheme.onSurfaceVariant,
                )
                Column(Modifier.focusGroup(), verticalArrangement = Arrangement.spacedBy(metrics.u(32) - metrics.focusRing * 2)) {
                    for (row in TvTheme.all.chunked(3)) {
                        Row(horizontalArrangement = Arrangement.spacedBy(metrics.u(32) - metrics.focusRing * 2)) {
                            for (theme in row) {
                                val on = look.theme == theme.id
                                Pressable(
                                    { TvLookStore.pick(theme.id, api) }, Modifier.weight(1f), shape = metrics.corner(14), fill = scheme.surface,
                                    label = theme.name, selected = on, takeFocus = on,
                                ) { ThemeCard(theme, on, look, app) }
                            }
                            repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                        }
                    }
                }
                if (look.source == TvLookChoice.Source.You) {
                    SheetButton("Follow the app's theme and the server's choice again", { TvLookStore.change(mapOf("theme" to null), api) }, kind = SheetKind.Quiet)
                }
                if (look.theme == "custom") {
                    Choice("Layout", look.shape.id, TvShape.entries.map { it.id to it.title }) { TvLookStore.change(mapOf("custom" to TvLookStore.custom(it, look.font)), api) }
                    Choice("Type", look.font, listOf("" to "As the layout has it", "system" to "Plain", "narrow" to "Narrow", "mono" to "Typewriter", "serif" to "Newspaper")) {
                        TvLookStore.change(mapOf("custom" to TvLookStore.custom(look.shape.id, it)), api)
                    }
                }
                Choice("Row size", look.density, listOf("compact" to "Compact", "normal" to "Normal", "large" to "Large")) { change("density", it) }
                Choice("Hours across", look.hours.toString(), listOf("0.0" to "What fits", "1.5" to "1½", "2.0" to "2", "3.0" to "3", "4.0" to "4")) {
                    change("hours", it.toDoubleOrNull() ?: 0.0)
                }
                Choice("Preview", look.preview, listOf("highlight" to "What's highlighted", "last" to "The last channel", "off" to "Off")) { change("preview", it) }
                Choice("Preview side", look.previewSide, listOf("left" to "Left", "right" to "Right")) { change("previewSide", it) }
                Column(verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                    Toggle("The line at the current time", look.nowLine) { change("nowLine", it) }
                    Toggle("How far into what's on now", look.progress) { change("progress", it) }
                    Toggle("Episode names and details in the grid", look.subtitles) { change("subtitles", it) }
                    Toggle("Channel logos", look.logos) { change("logos", it) }
                    Toggle("The programme's picture at the top", look.art) { change("art", it) }
                    Toggle("Preview sound", look.previewSound) { change("previewSound", it) }
                }
                Text("Colours are chosen on the server's page, under Look, and they come here too.", style = MaterialTheme.typography.secondary, color = scheme.onSurfaceVariant)
                SheetButton("Done", onClose, kind = SheetKind.Primary)
            }
        }
    }
}

@Composable
private fun Choice(title: String, value: String, options: List<Pair<String, String>>, set: (String) -> Unit) {
    val metrics = LocalMetrics.current
    Column(verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Text(title, style = MaterialTheme.typography.section, color = MaterialTheme.colorScheme.onBackground, modifier = Modifier.semantics { heading() })
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .padding(vertical = metrics.u(24) - metrics.focusRing, horizontal = metrics.u(8) - metrics.focusRing)
                .focusGroup(),
            horizontalArrangement = Arrangement.spacedBy(metrics.u(16) - metrics.focusRing * 2),
        ) {
            for ((id, name) in options) SheetButton(name, { set(id) }, selected = value == id)
        }
    }
}

@Composable
private fun Toggle(title: String, on: Boolean, set: (Boolean) -> Unit) {
    SheetButton(title, { set(!on) }, selected = on, icon = if (on) TvSymbols.Ticked else TvSymbols.Unticked)
}

// A theme drawn as a small picture of itself: the guide's own proportions, in its own colours.
@Composable
private fun ThemeCard(theme: TvTheme, on: Boolean, current: TvLookChoice, app: com.wittywilla.wittymediaclient.net.TvAppColours) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    val shape = if (theme.id == "custom") current.shape else theme.shape
    val colours = remember(theme.id, on, current.overrides, app) {
        TvLook.resolve(TvSaved(theme = theme.id, themeColours = if (on) mapOf(theme.id to current.overrides) else null), null, null, null, null, app).colours
    }
    val p = remember(colours) { TvPaint(colours) }
    Column(
        Modifier
            .fillMaxWidth()
            .border(metrics.u(3), if (on) scheme.primary else Color.Transparent, metrics.corner(14))
            .padding(metrics.u(12)),
        verticalArrangement = Arrangement.spacedBy(metrics.u(8)),
    ) {
        Canvas(Modifier.fillMaxWidth().aspectRatio(16f / 9f).clip(metrics.corner(6))) { drawThemePicture(shape, p) }
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(theme.name, style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.Bold), color = scheme.onBackground, modifier = Modifier.weight(1f))
            if (on) Icon(TvSymbols.Chosen, contentDescription = null, tint = scheme.primary, modifier = Modifier.size(metrics.u(40)))
        }
        Text(theme.blurb, style = MaterialTheme.typography.caption, color = scheme.onSurfaceVariant, maxLines = 3, minLines = 3, overflow = TextOverflow.Ellipsis)
    }
}

private fun DrawScope.drawThemePicture(shape: TvShape, p: TvPaint) {
    val w = size.width
    val h = size.height
    val r = if (shape == TvShape.Receiver || shape == TvShape.Teletext || shape == TvShape.Listings) 0f else 3 * density * TV_UNIT
    val previewLeft = shape == TvShape.Cinema
    fun box(colour: Color, x: Float, y: Float, bw: Float, bh: Float, radius: Float = r) = drawRoundRect(colour, Offset(x, y), Size(bw, bh), CornerRadius(radius))
    fun outline(colour: Color, x: Float, y: Float, bw: Float, bh: Float) {
        val s = density * TV_UNIT
        drawRoundRect(colour, Offset(x + s / 2, y + s / 2), Size(bw - s, bh - s), CornerRadius(r), style = Stroke(s))
    }
    drawRect(p.bg)
    val wordsX = w * if (previewLeft) 0.62f else 0.06f
    box(if (shape == TvShape.Teletext) p.accent else p.text, wordsX, h * 0.13f, w * 0.34f, h * 0.08f)
    box(p.soft, wordsX, h * 0.26f, w * 0.24f, h * 0.04f)
    box(p.hi, wordsX, h * 0.34f, w * 0.14f, h * 0.07f, if (shape == TvShape.Modern) 20 * density * TV_UNIT else r)
    val pw = w * if (previewLeft) 0.52f else if (shape == TvShape.Compact) 0.2f else 0.36f
    val ph = h * if (previewLeft) 0.56f else if (shape == TvShape.Compact) 0.22f else 0.34f
    val px = if (previewLeft) w * 0.05f else w * if (shape == TvShape.Compact) 0.74f else 0.58f
    drawRect(Color.White.copy(alpha = 0.18f), Offset(px, h * 0.08f), Size(pw, ph))
    drawRect(p.line, Offset(px, h * 0.08f), Size(pw, ph), style = Stroke(density * TV_UNIT))
    val gap = if (shape == TvShape.Receiver || shape == TvShape.Listings || shape == TvShape.Teletext) 0f else w * 0.01f
    val rowH = h * if (shape == TvShape.Compact) 0.07f else if (previewLeft) 0.09f else 0.12f
    for (i in 0 until 3) {
        val y = h * ((if (previewLeft) 0.67f else if (shape == TvShape.Compact) 0.32f else 0.48f) + i * (if (previewLeft) 0.11f else if (shape == TvShape.Compact) 0.12f else 0.15f))
        var x = w * 0.06f
        val total = w * 0.88f
        val a = w * 0.18f
        val b = w * 0.3f
        val c = total - a - b - gap * 2
        if (shape == TvShape.Outline) outline(p.line, x, y, a, rowH) else box(p.ch, x, y, a, rowH)
        x += a + gap
        if (i == 1) box(p.hi, x, y, b, rowH) else if (shape == TvShape.Outline) outline(if (i == 0) p.accent else p.line, x, y, b, rowH) else box(p.live, x, y, b, rowH)
        x += b + gap
        if (shape == TvShape.Outline) outline(p.line, x, y, c, rowH) else box(p.cell, x, y, c, rowH)
    }
    if (shape != TvShape.Teletext && shape != TvShape.Listings) {
        drawRect(p.accent, Offset(w * 0.42f, h * if (previewLeft) 0.65f else 0.44f), Size(maxOf(1f, w * 0.01f), h * if (previewLeft) 0.32f else 0.48f))
    }
}
