package com.wittywilla.wittymediaclient.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.os.ConfigurationCompat
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import com.wittywilla.wittymediaclient.net.Api
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.BrandLogoAnswer
import com.wittywilla.wittymediaclient.net.TitleAttached
import com.wittywilla.wittymediaclient.net.TitleListings
import com.wittywilla.wittymediaclient.net.TitleTarget
import com.wittywilla.wittymediaclient.net.isListening
import com.wittywilla.wittymediaclient.net.notice
import java.util.Date
import java.util.Locale

// The pieces an item's and a show's page share at phone size, as the website draws them (styles.css's detail rules,
// player.css's seasons, episodes and playlist, components/edit/titlepage.css and brandlogo.css). The words are
// TitleLook's.

// A negative top margin: the column starts `by` higher and the page after it moves up with it.
fun Modifier.pullUp(by: Dp): Modifier = this.layout { measurable, constraints ->
    val placeable = measurable.measure(constraints)
    val up = by.roundToPx()
    layout(placeable.width, (placeable.height - up).coerceAtLeast(0)) { placeable.place(0, -up) }
}

// Out to the screen's edges through the page's `side` either way, as the website's rows are.
fun Modifier.bleed(side: Dp): Modifier = this.layout { measurable, constraints ->
    val extra = side.roundToPx() * 2
    val wide = constraints.maxWidth + extra
    val placeable = measurable.measure(constraints.copy(minWidth = wide, maxWidth = wide))
    layout(constraints.maxWidth, placeable.height) { placeable.place(-extra / 2, 0) }
}

// MARK: the top of the page

// The poster: 132 wide, radius 14, the large shadow, on the card colour. Blank where there's none; a frame of the
// video is shown whole, 16:9, on a colour of its own worked out from the title.
@Composable
fun TitlePoster(url: String?, frameOf: String? = null) {
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.width(132.dp).aspectRatio(2f / 3f).cssShadow(10.dp, 30.dp, Color(0x73000000), 14.dp).clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant)) {
        if (frameOf != null) {
            val hue = TitleLook.artHue(frameOf).toFloat()
            Box(Modifier.fillMaxSize().angledGradient(170f, Color.hsl(hue, 0.26f, 0.26f), Color.hsl((hue + 40) % 360, 0.34f, 0.11f)), contentAlignment = Alignment.Center) {
                if (url != null) WebArt(url, "", 132.dp, 16f / 9f, Modifier.fillMaxWidth().aspectRatio(16f / 9f).cssShadow(6.dp, 18.dp, Color(0x66000000), 0.dp), placeholderless = true)
            }
        } else if (url != null) {
            WebArt(url, "", 132.dp, 2f / 3f, Modifier.fillMaxSize(), placeholderless = true)
        }
    }
}

// A picture shown no bigger than it was drawn (a pixel counted as a dp, as a browser counts it) and no bigger than
// its room, keeping its shape. `instead` shows until it has come, and if it can't.
@Composable
private fun FittedPicture(url: String?, maxWidth: Dp, maxHeight: Dp, pixels: Int, modifier: Modifier = Modifier, instead: @Composable () -> Unit) {
    val context = LocalContext.current
    var drawn by remember(url) { mutableStateOf<Pair<Int, Int>?>(null) }
    var failed by remember(url) { mutableStateOf(false) }
    val size = drawn
    if (size == null || failed || url == null) instead()
    if (url == null || failed) return
    val request = remember(url, pixels) { ImageRequest.Builder(context).data(url).size(pixels, pixels).build() }
    // Nothing to see while it comes, plate and all.
    val shown = if (size == null) Modifier.size(0.dp) else {
        val (w, h) = size
        val aspect = w.toFloat() / h.coerceAtLeast(1)
        val width = minOf(maxWidth.value, maxHeight.value * aspect, w.toFloat())
        modifier.size(width.dp, (width / aspect).dp)
    }
    AsyncImage(
        request, null, shown, contentScale = ContentScale.Fit,
        onSuccess = { drawn = it.result.image.width to it.result.image.height }, onError = { failed = true },
    )
}

// The title in 28 on a phone (growing with the width to 44), semibold, with its soft shadow; or the title's logo where
// it has one, no wider than 420 or the column and no taller than 160. The words stay until the logo has come.
@Composable
fun TitleHeading(title: String, logo: String?, column: Dp) {
    val size = TitleLook.titleSize(LocalConfiguration.current.screenWidthDp.toDouble()).toFloat()
    val density = LocalDensity.current
    // CSS's 12 blur is a spread of 6 either way, which a text shadow's radius of about 9.5 draws.
    val shadow = with(density) { androidx.compose.ui.graphics.Shadow(Color(0x73000000), Offset(0f, 2.dp.toPx()), 9.5.dp.toPx()) }
    Box(Modifier.padding(bottom = 8.dp).semantics { heading(); contentDescription = title }) {
        FittedPicture(logo, minOf(420.dp, column), 160.dp, 840, Modifier.clearAndSetSemantics {}) {
            Text(
                title, color = MaterialTheme.colorScheme.onBackground, fontSize = size.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.022).em,
                lineHeight = (size * 1.14f).sp, style = TextStyle(shadow = shadow), modifier = Modifier.clearAndSetSemantics {},
            )
        }
    }
}

// The website's `.meta`: facts in rows that wrap, 16 apart, each in the middle of its row, in 14 textSecondary. A
// fact has a dot 10 to its left; the row is clipped, so one starting a line shows none.
@Composable
fun MetaRow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    FlowRow(
        modifier.clipToBounds(), horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(2.dp),
        itemVerticalAlignment = Alignment.CenterVertically,
    ) { content() }
}

@Composable
fun Dotted(dot: Boolean, content: @Composable () -> Unit) {
    Box {
        content()
        if (dot) Text("·", color = LocalExtraColours.current.hint, fontSize = 14.sp, modifier = Modifier.offset(x = (-10).dp).clearAndSetSemantics {})
    }
}

@Composable
fun MetaWords(words: String) {
    Text(words, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 14.sp)
}

// A rating box (`.pill`): 20 high, 8 inside, outlined in the text colour at 20%, radius 4, 11 semibold.
@Composable
fun MetaPill(words: String) {
    val scheme = MaterialTheme.colorScheme
    Box(Modifier.heightIn(min = 20.dp).border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(4.dp)).padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
        Text(words, color = scheme.onSurfaceVariant, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.02.em, maxLines = 1)
    }
}

// ★ 7.9, the 14 star in warn, 3 before the number.
@Composable
fun MetaStar(rating: Double) {
    val words = String.format(Locale.ROOT, "%.1f", rating)
    Row(Modifier.clearAndSetSemantics { contentDescription = "Rated $words" }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        Icon(WebIcons.Star, null, tint = LocalExtraColours.current.warn, modifier = Modifier.size(14.dp))
        MetaWords(words)
    }
}

// MARK: logos

// Which of a logo's pictures reads on this theme: the page's background decides, as the website's logoVariant does.
@Composable
private fun logoVariant(logo: BrandLogoAnswer): String {
    if (logo.opaque) return "original"
    val bg = MaterialTheme.colorScheme.background
    return if (0.2126 * bg.red * 255 + 0.7152 * bg.green * 255 + 0.0722 * bg.blue * 255 > 140) "dark" else "white"
}

// A studio's, a network's or a streaming service's logo from the logo service, or its name (`BrandLogo`). A logo with
// its own background is on a white plate, radius 4, 4 inside. The name is semibold, a little tight, centred.
@Composable
fun BrandLogo(api: Api, name: String, logo: BrandLogoAnswer?, maxWidth: Dp, maxHeight: Dp, size: Int, colour: Color) {
    val url = logo?.takeIf { it.has }?.let { api.logoImageUrl(it, logoVariant(it)) }
    val plate = logo?.opaque == true
    val room = if (plate) 8.dp else 0.dp
    val pixels = with(LocalDensity.current) { 240.dp.roundToPx() }
    FittedPicture(url, maxWidth - room, maxHeight - room, pixels, if (plate) Modifier.clip(RoundedCornerShape(4.dp)).background(Color.White).padding(4.dp) else Modifier) {
        Text(
            name, color = colour, fontSize = size.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.012).em, lineHeight = (size * 1.14f).sp,
            textAlign = TextAlign.Center, maxLines = if (maxHeight < 30.dp) 1 else Int.MAX_VALUE, modifier = Modifier.widthIn(max = maxWidth),
        )
    }
}

// A studio or a streaming service as a tile (`.title-brand`): 120 by 56, 8 and 12 inside, radius 10, card colour.
@Composable
fun BrandTile(api: Api, name: String, logo: BrandLogoAnswer?, open: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(open, Modifier.size(120.dp, 56.dp), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = name, pressScale = 0.975f, ring = false) {
        Box(Modifier.fillMaxSize().padding(horizontal = 12.dp, vertical = 8.dp), contentAlignment = Alignment.Center) {
            BrandLogo(api, name, logo, 96.dp, 40.dp, 12, scheme.onBackground)
        }
    }
}

// What the logo service has for these names, kept by BrandLogoAnswer.key. Nothing when it can't say.
suspend fun lookUpLogos(api: Api, names: List<Pair<String, String>>): Map<String, BrandLogoAnswer> {
    if (names.isEmpty()) return emptyMap()
    return runCatching { api.lookUpLogos(names) }.getOrDefault(emptyList()).associateBy { BrandLogoAnswer.key(it.kind, it.name) }
}

// MARK: small print

private val MARKDOWN_LINK = Regex("""\[([^\]]*)\]\(([^)]*)\)""")

// Markdown's links read out of a line: each part's words, and where it goes when it's a link.
fun markdownParts(text: String): List<Pair<String, String?>> {
    val parts = mutableListOf<Pair<String, String?>>()
    var at = 0
    for (match in MARKDOWN_LINK.findAll(text)) {
        if (match.range.first > at) parts += text.substring(at, match.range.first) to null
        parts += match.groupValues[1] to match.groupValues[2]
        at = match.range.last + 1
    }
    if (at < text.length) parts += text.substring(at) to null
    return parts
}

// Fine print (`.fine-print`): 12 in textHint, its links in accentText and underlined, opening in the browser.
@Composable
fun FinePrint(markdown: String, modifier: Modifier = Modifier) {
    val extra = LocalExtraColours.current
    val link = TextLinkStyles(SpanStyle(color = extra.accentText, textDecoration = TextDecoration.Underline))
    val words = buildAnnotatedString {
        markdownParts(markdown).forEach { (text, url) ->
            if (url == null) append(text) else withLink(LinkAnnotation.Url(url, link)) { append(text) }
        }
    }
    Text(words, color = extra.hint, fontSize = 12.sp, lineHeight = 1.55.em, modifier = modifier)
}

// One of the server's short legal notices (`.legal-note`), with its link to the Legal page: 12 in textHint, 1.5 apart.
@Composable
fun LegalLine(nav: Nav, kind: String, modifier: Modifier = Modifier) {
    val note = nav.legal?.notice(kind) ?: return
    val extra = LocalExtraColours.current
    val words = buildAnnotatedString {
        append(note.words + " ")
        withLink(LinkAnnotation.Clickable("legal", TextLinkStyles(SpanStyle(color = extra.accentText, textDecoration = TextDecoration.Underline))) { nav.push(Route.Page(note.path, note.link)) }) {
            append(note.link)
        }
    }
    Text(words, color = extra.hint, fontSize = 12.sp, lineHeight = 18.sp, modifier = modifier)
}

// MARK: the end of the page

// "‹ Back to library" (`.back-link`): 44 high and round, 4 and 12 inside, starting 4 out, an 18 chevron, 14 semibold
// in textSecondary.
@Composable
fun TitleBackLink(words: String, modifier: Modifier = Modifier, go: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(go, modifier.offset(x = (-4).dp).heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = Color.Transparent, label = words, ring = false) {
        Row(Modifier.heightIn(min = 44.dp).padding(start = 4.dp, end = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Icon(WebIcons.Left, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
            Text(words, color = scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
        }
    }
}

// The website's EmptyState: in the middle, 64 above and below, a 56 circle of the card colour with the 26 icon in
// textHint, the title 17, the words 14 in textSecondary, then what to do.
@Composable
fun TitleEmpty(icon: ImageVector, title: String, words: String, action: (@Composable () -> Unit)? = null) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().padding(top = LocalTopRoom.current).padding(vertical = 64.dp, horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.padding(bottom = 16.dp).size(56.dp).clip(CircleShape).background(scheme.surfaceVariant), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(26.dp))
        }
        Text(title, color = scheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 4.dp).semantics { heading() })
        if (words.isNotEmpty()) Text(words, color = scheme.onSurfaceVariant, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 360.dp).padding(bottom = 16.dp))
        action?.invoke()
    }
}

// MARK: what both pages show under the synopsis

// A heading inside the extras: 17 semibold, 8 above what it names.
@Composable
private fun ExtrasHeading(words: String) {
    Text(
        words, color = MaterialTheme.colorScheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, letterSpacing = (-0.012).em,
        modifier = Modifier.padding(bottom = 8.dp).semantics { heading() },
    )
}

// A chip (`.chip`): 44 high on a touch screen, 12 inside, round, outlined in the text colour at 20%, 13 medium in
// textSecondary.
@Composable
private fun TagChip(words: String, open: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(open, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = Color.Transparent, label = words, pressScale = 0.975f, ring = false) {
        Box(Modifier.heightIn(min = 44.dp).border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(50)).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
            Text(words, color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1)
        }
    }
}

// The website's TitleExtras: who made it, its editions and tags, its studios, other versions, bonus features, and
// where it's listed if the owner turned that on. 16 apart.
@Composable
fun TitleExtras(nav: Nav, target: TitleTarget, attached: TitleAttached, listings: TitleListings?, libraryId: Long?, logos: Map<String, BrandLogoAnswer>, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val api = nav.app.api
    val platforms = listings?.platforms.orEmpty()
    val logoShown = attached.studios.any { logos[BrandLogoAnswer.key("studio", it)]?.has == true } || platforms.any { logos[BrandLogoAnswer.key("platform", it.name)]?.has == true }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        if (attached.director.isNotEmpty() || attached.edition.isNotEmpty() || attached.tags.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp), itemVerticalAlignment = Alignment.CenterVertically) {
                if (attached.director.isNotEmpty()) {
                    val words = buildAnnotatedString {
                        withStyle(SpanStyle(color = extra.hint)) { append(if (target == TitleTarget.Show) "Created by" else "Directed by") }
                        append(" " + attached.director)
                    }
                    Text(words, color = scheme.onBackground, fontSize = 14.sp)
                }
                attached.edition.forEach { MetaPill(it) }
                attached.tags.forEach { tag -> TagChip(tag) { if (libraryId != null) nav.openLibraryWith(libraryId, "tag", tag, TitleLook.tagPath(libraryId, tag)) } }
            }
        }
        if (attached.studios.isNotEmpty() && libraryId != null) {
            FlowRow(Modifier.semantics { contentDescription = "Studios" }, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                attached.studios.forEach { name -> BrandTile(api, name, logos[BrandLogoAnswer.key("studio", name)]) { nav.push(Route.Page(TitleLook.brandPath("studio", name, libraryId))) } }
            }
        }
        if (attached.versions.isNotEmpty()) {
            Column {
                ExtrasHeading("Other versions")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    attached.versions.forEach { v -> WebButton(TitleLook.versionLabel(v), { nav.push(Route.Item(v.item.id)) }) }
                }
            }
        }
        if (attached.extras.isNotEmpty()) {
            Column {
                ExtrasHeading("Bonus features")
                // The website's row: out to the screen's edges, 12 above the cards and 16 below.
                Box(Modifier.bleed(16.dp)) {
                    HubRow {
                        items(attached.extras.distinctBy { it.item.id }, key = { it.item.id }) { x ->
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                WebItemCard(nav, x.item, forceWide = true)
                                Text(TitleLook.extraName(x.link?.extraType), color = extra.hint, fontSize = 15.sp)
                            }
                        }
                    }
                }
            }
        }
        if (platforms.isNotEmpty() && listings != null && libraryId != null) {
            Column {
                ExtrasHeading("Also listed on")
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    platforms.forEach { p -> BrandTile(api, p.name, logos[BrandLogoAnswer.key("platform", p.name)]) { nav.openLibraryWith(libraryId, "platform", p.key, TitleLook.platformPath(libraryId, p.key)) } }
                }
                val locale = ConfigurationCompat.getLocales(LocalConfiguration.current)[0] ?: Locale.ROOT
                val note = buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append("Nothing plays from these services.") }
                    append(" " + TitleLook.listedNote(listings) { shortDate(it, locale) })
                }
                Text(note, color = extra.hint, fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                LegalLine(nav, "listings", Modifier.padding(top = 16.dp))
            }
        }
        // Its own 16 on top of the column's, as the website's note keeps its margin in a flex column.
        if (logoShown) LegalLine(nav, "logos", Modifier.padding(top = 16.dp))
    }
}

// A date as the browser's toLocaleDateString writes it: 05/11/2026 in Britain.
private fun shortDate(seconds: Long, locale: Locale): String {
    val pattern = android.text.format.DateFormat.getBestDateTimePattern(locale, "dMyyyy")
    return java.text.SimpleDateFormat(pattern, locale).format(Date(seconds * 1000))
}

// A library's page with something chosen, as the website's /library/3?genre=Drama: the app's own page for a film or TV
// library, the server's for any other.
fun Nav.openLibraryWith(library: Long, key: String, value: String, path: String) {
    val entry = menu.firstOrNull { it.key == "lib:$library" }
    val own = (entry?.route as? Route.Library)?.library
    if (own != null && !own.isListening && !app.isTv) push(Route.Library(own, mapOf(key to value)))
    else push(Route.Page(path, entry?.label.orEmpty()))
}

// A library's own page, from a caption or Back to library.
fun Nav.openLibraryPage(library: Long) {
    val entry = menu.firstOrNull { it.key == "lib:$library" }
    if (entry != null) openMenu(entry) else push(Route.Page("/library/$library"))
}

// MARK: a show's seasons and episodes

// A season as its poster (`.season-tab`), 108 wide, radius 10, the card colour under it and a hairline over it; the
// chosen one ringed in the accent, 2 out. Its name 13 semibold 8 below, and how many are left in 12 textHint.
@Composable
fun SeasonTab(title: String, line: String, poster: String?, chosen: Boolean, choose: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val spoken = listOf(title, line).filter { it.isNotEmpty() }.joinToString(", ")
    Pressable(choose, Modifier.width(108.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = spoken, selected = chosen, pressScale = 0.975f, ring = false, clip = false) {
        Column(Modifier.width(108.dp)) {
            Box(
                Modifier.fillMaxWidth().aspectRatio(2f / 3f).then(if (chosen) Modifier.ringOutside(RoundedCornerShape(10.dp), scheme.primary, 2.dp, 2.dp) else Modifier)
                    .clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant),
            ) {
                if (poster != null) WebArt(poster, "", 108.dp, 2f / 3f, Modifier.fillMaxSize(), placeholderless = true)
                Box(Modifier.fillMaxSize().border(1.dp, Color(0x14FFFFFF), RoundedCornerShape(10.dp)))
            }
            Text(title, color = scheme.onBackground, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp))
            if (line.isNotEmpty()) Text(line, color = LocalExtraColours.current.hint, fontSize = 12.sp)
        }
    }
}

// Layout (`.view-toggle`): the word in 13 textHint, then Cards and Playlist together on the card colour, each 44 high
// on a touch screen, 12 inside, 13 semibold, the chosen one in the page's colour on the text colour; and Use default
// when this show has its own. 12 apart.
@Composable
fun LayoutSwitch(current: String, own: Boolean, modifier: Modifier = Modifier, choose: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("Layout", color = LocalExtraColours.current.hint, fontSize = 13.sp)
        Row(Modifier.clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            listOf("cards" to "Cards", "list" to "Playlist").forEach { (view, words) ->
                val on = current == view
                Pressable({ choose(view) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(7.dp), fill = if (on) scheme.onBackground else Color.Transparent, label = words, selected = on, ring = false) {
                    Box(Modifier.heightIn(min = 44.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        Text(words, color = if (on) scheme.background else scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                }
            }
        }
        if (own) WebButton("Use default", { choose("") }, WebButtonKind.Ghost, small = true)
    }
}

// An episode (`.episode`): the picture 132 wide, radius 10, which plays it, with how far through and a tick once
// watched; beside it, 12 over, the number in 12 textHint before the title in 15 semibold, when it aired and how long
// in 12 textHint, and two lines of what happens in 13 textSecondary. Anywhere else on the row opens its page.
@Composable
fun EpisodeRow(nav: Nav, ep: Item, play: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val p = ep.progress
    val progress = if (p != null && p.durationSec > 0 && !p.watched) (p.positionSec / p.durationSec).coerceIn(0.0, 1.0).toFloat().takeIf { it > 0f } else null
    val number = episodeLabel(ep)
    val line = TitleLook.episodeLine(ep)
    Pressable({ nav.push(Route.Item(ep.id)) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp), fill = Color.Transparent, label = listOf(number, ep.title, line).filter { it.isNotEmpty() }.joinToString(", "), pressScale = 1f, ring = false) {
        Row(Modifier.fillMaxWidth().padding(8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Pressable(play, Modifier.width(132.dp).aspectRatio(16f / 9f), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = "Play ${ep.title}", pressScale = 0.975f, ring = false) {
                Box(Modifier.fillMaxSize()) {
                    if (ep.poster.isNotEmpty()) WebArt(nav.app.api.posterUrl(ep), "", 132.dp, 16f / 9f, Modifier.fillMaxSize(), placeholderless = true)
                    if (progress != null) Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(3.dp).background(Color(0x47FFFFFF))) {
                        Box(Modifier.fillMaxWidth(progress).height(3.dp).background(scheme.primary))
                    }
                    if (p?.watched == true) Box(Modifier.align(Alignment.TopEnd).padding(8.dp).size(20.dp).clip(CircleShape).background(Color(0xAD000000)), contentAlignment = Alignment.Center) {
                        Icon(WebIcons.Check, "Watched", tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                    Box(Modifier.fillMaxSize().border(1.dp, Color(0x14FFFFFF), RoundedCornerShape(10.dp)))
                }
            }
            Column(Modifier.weight(1f).padding(top = 2.dp)) {
                val title = buildAnnotatedString {
                    if (number.isNotEmpty()) {
                        withStyle(SpanStyle(color = extra.hint, fontSize = 12.sp)) { append(number) }
                        // The number's 6 to its right, and the space after it.
                        withStyle(SpanStyle(letterSpacing = 6.sp)) { append(" ") }
                    }
                    append(ep.title)
                }
                Text(title, color = scheme.onBackground, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = 1.32.em)
                if (line.isNotEmpty()) Text(line, color = extra.hint, fontSize = 12.sp, modifier = Modifier.padding(top = 2.dp))
                if (ep.overview.isNotEmpty()) Text(ep.overview, color = scheme.onSurfaceVariant, fontSize = 13.sp, lineHeight = 1.5.em, maxLines = 2, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

// The website's Playlist (`.titles-table.episode-table`): a table of the season that scrolls sideways on a phone. The
// picture 52 wide, the number, the title, when it aired, how long, a tick or where it was left, and Play. Each column
// as wide as its widest cell; a row opens the episode.
@Composable
fun EpisodeTable(nav: Nav, episodes: List<Item>, play: (Item) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val strong = scheme.onBackground.copy(alpha = 0.2f)
    val numbers = TextStyle(fontSize = 14.sp, fontFeatureSettings = "tnum")
    Box(Modifier.horizontalScroll(rememberScrollState())) {
        Table(7) {
            listOf("", "#", "Title", "Aired", "Length", "", "").forEach { head ->
                TableCell(strong, top = 8.dp) {
                    Text(head.uppercase(Locale.ROOT), color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, softWrap = false)
                }
            }
            episodes.forEach { ep ->
                val open = { nav.push(Route.Item(ep.id)) }
                TableCell(scheme.outline, end = 0.dp, open = open) {
                    Box(Modifier.size(52.dp, 29.25.dp).clip(RoundedCornerShape(4.dp)).background(scheme.surfaceVariant)) {
                        if (ep.poster.isNotEmpty()) WebArt(nav.app.api.posterUrl(ep), "", 52.dp, 16f / 9f, Modifier.fillMaxSize(), placeholderless = true)
                    }
                }
                TableCell(scheme.outline, open = open) { Text(TitleLook.playlistNumber(ep), color = extra.hint, fontWeight = FontWeight.SemiBold, style = numbers, softWrap = false) }
                TableCell(scheme.outline, open = open) { Text(ep.title, color = scheme.onBackground, style = numbers, softWrap = false) }
                TableCell(scheme.outline, open = open) { Text(ep.aired, color = extra.hint, style = numbers, softWrap = false) }
                TableCell(scheme.outline, open = open) { Text(if (ep.runtimeSec > 0) TitleLook.clock(ep.runtimeSec) else "", color = scheme.onBackground, style = numbers, softWrap = false) }
                TableCell(scheme.outline, open = open) {
                    val p = ep.progress
                    when {
                        p?.watched == true -> Icon(WebIcons.Check, "Watched", tint = extra.hint, modifier = Modifier.size(16.dp))
                        p != null && p.resumeSec > 0 -> Text(TitleLook.clock(p.positionSec), color = extra.hint, style = numbers, softWrap = false)
                        else -> Text("", style = numbers)
                    }
                }
                TableCell(scheme.outline, open = open) { WebButton("Play", { play(ep) }, WebButtonKind.Secondary, WebIcons.Play, small = true) }
            }
        }
    }
}

// A cell: 12 at the sides, 10 above and below (a head's 8), a hairline along its foot, its content in the middle of its
// row's height.
@Composable
private fun TableCell(line: Color, top: Dp = 10.dp, end: Dp = 12.dp, open: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Box(
        Modifier.then(if (open != null) Modifier.clickable(remember { MutableInteractionSource() }, null, onClick = open) else Modifier)
            .drawBehind { drawRect(line, Offset(0f, size.height - 1.dp.toPx()), Size(size.width, 1.dp.toPx())) }
            .padding(start = 12.dp, end = end, top = top, bottom = top + 1.dp),
        contentAlignment = Alignment.CenterStart,
    ) { content() }
}

// A table: its cells row by row, each column as wide as its widest cell and each row as tall as its tallest.
@Composable
private fun Table(columns: Int, content: @Composable () -> Unit) {
    Layout(content) { measurables, _ ->
        val rows = (measurables.size + columns - 1) / columns
        val widths = IntArray(columns)
        measurables.forEachIndexed { i, m -> widths[i % columns] = maxOf(widths[i % columns], m.maxIntrinsicWidth(Constraints.Infinity)) }
        val heights = IntArray(rows)
        measurables.forEachIndexed { i, m -> heights[i / columns] = maxOf(heights[i / columns], m.minIntrinsicHeight(widths[i % columns])) }
        val placeables = measurables.mapIndexed { i, m -> m.measure(Constraints.fixed(widths[i % columns], heights[i / columns])) }
        layout(widths.sum(), heights.sum()) {
            var y = 0
            for (r in 0 until rows) {
                var x = 0
                for (c in 0 until columns) {
                    placeables.getOrNull(r * columns + c)?.place(x, y)
                    x += widths[c]
                }
                y += heights[r]
            }
        }
    }
}
