package com.wittywilla.wittymediaclient.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.StartOffset
import androidx.compose.animation.core.StartOffsetType
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import androidx.compose.ui.zIndex
import androidx.core.os.ConfigurationCompat
import coil3.SingletonImageLoader
import coil3.request.ImageRequest
import coil3.request.allowHardware
import coil3.toBitmap
import com.wittywilla.wittymediaclient.net.Album
import com.wittywilla.wittymediaclient.net.Artist
import com.wittywilla.wittymediaclient.net.ArtistInfo
import com.wittywilla.wittymediaclient.net.Collection
import com.wittywilla.wittymediaclient.net.CollectionItems
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.MusicHome
import com.wittywilla.wittymediaclient.net.keepsPlace
import com.wittywilla.wittymediaclient.net.pagePath
import com.wittywilla.wittymediaclient.player.Start
import com.wittywilla.wittymediaclient.player.clock
import com.wittywilla.wittymediaclient.player.placeOn
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Locale
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sin

// The website's music, audiobook and podcast pages on a phone (web/src/pages/AudioLibrary.tsx, music/parts.tsx,
// music/CoverFlow.tsx, music/ArtistPage.tsx, music.css, audio.css), as the iPhone has them (MusicPages.swift): a
// library's Home with its cover flow and rows, and its Albums, Artists, Songs and Playlists; an album, a book or a
// podcast; an artist or an author. The words and order are in MusicLook. Android TV keeps its own (ListeningScreens.kt).

// Something just done, said in a toast at the foot of the page, as the website's toast() does.
internal val LocalSay = staticCompositionLocalOf<(String) -> Unit> { {} }

// The website's --hover and --scrim.
private const val HOVER = 0.07f
private val SCRIM = Color(0xAD000000)
private val E3 = Color(0x73000000)
private const val BODY_LINE = 1.55f

// Figures all the same width, as the website's tabular-nums.
private val NUMBERS = TextStyle(fontFeatureSettings = "tnum")

@Composable
private fun pageLocale(): Locale = ConfigurationCompat.getLocales(LocalConfiguration.current)[0] ?: Locale.ROOT

// MARK: a library

// Each library, album and artist page starts afresh, even when another takes its place without leaving it.
@Composable
fun PhoneMusicLibrary(nav: Nav, library: Library, chosen: Map<String, String> = emptyMap()) {
    key(library.id, chosen) { MusicLibraryPage(nav, library, chosen) }
}

@Composable
fun PhoneAlbum(nav: Nav, route: Route.Album) {
    key(route.key) { AlbumPage(nav, route) }
}

@Composable
fun PhoneArtist(nav: Nav, library: Long, name: String) {
    key(library, name) { ArtistPage(nav, library, name) }
}

@Composable
private fun MusicLibraryPage(nav: Nav, library: Library, chosen: Map<String, String>) {
    val api = nav.app.api
    val type = library.type
    val pods = type == "podcasts"
    val admin = nav.me?.isAdmin == true
    var tabKey by rememberSaveable(library.id) { mutableStateOf(MusicTab.of(chosen["tab"]).key) }
    // Music videos, when this person can see a music videos library.
    val videos = type == "music" && MusicVideos.available(nav.libraries)
    val tab = MusicTab.of(tabKey).takeIf { t -> MusicLook.tabs(type, videos).any { it.first == t } } ?: MusicTab.Home
    var sort by rememberSaveable(library.id) { mutableStateOf(MusicLook.startSort(tab, type)) }
    var desc by rememberSaveable(library.id) { mutableStateOf(false) }
    var view by rememberSaveable(library.id) { mutableStateOf(chosen["view"].orEmpty()) }
    var genre by rememberSaveable(library.id) { mutableStateOf("") }
    var more by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf("") }
    val say: (String) -> Unit = { toast = it }
    LaunchedEffect(library.id) { if (type == "music") nav.app.listening.loadLikes(library.id) }

    // A part starts afresh, as the website's link to it drops what the last one had chosen.
    fun choose(next: MusicTab, nextView: String = "") {
        tabKey = next.key
        sort = MusicLook.startSort(next, type)
        desc = false
        view = nextView
        genre = ""
    }
    val sorts = MusicLook.sorts(tab, type, view)
    val head: LazyListScope.() -> Unit = {
        item(key = "head") { MusicHeader(library, sorts, sort, desc, { k, d -> sort = k; desc = d }) { more = true } }
        item(key = "tabs") {
            Seg(MusicLook.tabs(type, videos), tab, "Parts of ${library.name}", Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 16.dp)) { choose(it) }
        }
    }
    val notice = if (pods) "webMedia" else "general"
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalSay provides say) {
            when (tab) {
                MusicTab.Home -> MusicHomeTab(nav, library, head, notice) { t, v -> choose(t, v) }
                MusicTab.Albums -> AlbumsTab(nav, library, sort, desc, genre, { genre = it }, head, notice)
                MusicTab.Artists -> ArtistsTab(nav, library, sort, desc, head, notice)
                MusicTab.Songs -> SongsTab(nav, library, view, { view = it }, sort, desc, genre, { genre = it }, head, notice)
                MusicTab.Videos -> MusicVideosTab(nav, library, head, notice)
                MusicTab.Playlists -> PlaylistsTab(nav, library, head, notice) { choose(MusicTab.Songs, it) }
            }
        }
        if (more) {
            // The header's tools on a phone (LibraryHeader's "⋯"): Scan for an administrator, and following a podcast.
            val rows = buildList {
                if (admin) add(SheetRow("Scan", WebIcons.Refresh) {
                    nav.app.scope.launch {
                        runCatching { api.scan(library.id) }.onSuccess { say("Scanning ${library.name}") }.onFailure { say(it.message.orEmpty()) }
                    }
                })
                if (pods && admin) add(SheetRow("Follow a podcast", null) { nav.push(Route.Page(library.pagePath(), library.name)) })
            }
            WebSheet(library.name, { more = false }) { SheetRows(rows) { more = false } }
        }
        Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = LocalBottomRoom.current - 4.dp))
    }
}

// The list every part of a library is: the header, the part's own rows, and the foot of the page.
@Composable
private fun MusicList(
    nav: Nav, head: LazyListScope.() -> Unit, notice: String, modifier: Modifier = Modifier, state: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit,
) {
    TracksScroll(state)
    LazyColumn(modifier.fillMaxSize(), state = state, contentPadding = PaddingValues(top = LocalTopRoom.current, bottom = LocalBottomRoom.current)) {
        head()
        content()
        item(key = "foot") { PageFoot(nav, notice) }
    }
}

// The library's header on a phone (LibraryHeader, music.css): the bar in the page colour, 12 by 16 inside, with the
// name kept for screen readers only and "⋯" at the end; under it SORT and the sorts, when the part has any.
@Composable
private fun MusicHeader(library: Library, sorts: List<MusicLook.Sort>, sort: String, desc: Boolean, chooseSort: (String, Boolean) -> Unit, more: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    Column(Modifier.fillMaxWidth().background(scheme.background).padding(horizontal = 16.dp, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            // On a phone the strip above already says which library this is, so its name is for screen readers only.
            val width = LocalConfiguration.current.screenWidthDp
            if (width > 600) {
                Text(
                    library.name, color = scheme.onBackground, fontSize = (20.8f + 0.009f * width).coerceAtMost(30f).sp, fontWeight = FontWeight.SemiBold,
                    letterSpacing = (-0.022).em, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).semantics { heading() },
                )
            } else {
                Box(Modifier.size(1.dp).semantics { heading(); contentDescription = library.name })
                Spacer(Modifier.weight(1f))
            }
            GhostSquare(WebIcons.More, 18.dp, "More for ${library.name}", more)
        }
        if (sorts.isNotEmpty()) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("SORT", color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.07.em)
                Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()).padding(2.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    sorts.forEach { o ->
                        val on = o.key == sort
                        Pressable({ chooseSort(o.key, o.desc) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(50), fill = if (on) scheme.onBackground else Color.Transparent, label = o.label, selected = on, ring = false) {
                            Box(Modifier.heightIn(min = 44.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                                Text(o.label, color = if (on) scheme.background else scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                            }
                        }
                    }
                }
                sorts.firstOrNull { it.key == sort }?.let { current ->
                    GhostSquare(if (desc) WebIcons.SortDown else WebIcons.SortUp, 16.dp, MusicLook.directionWords(current.label, desc)) { chooseSort(current.key, !desc) }
                }
            }
        }
    }
}

// A ghost button that is only its icon: 44 square, radius 10, outlined in text at 20%.
@Composable
private fun GhostSquare(icon: ImageVector, iconSize: Dp, label: String, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(onClick, Modifier.size(44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = label, ring = false) {
        Box(Modifier.fillMaxSize().border(1.dp, scheme.onBackground.copy(alpha = 0.2f), RoundedCornerShape(10.dp)), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = scheme.onBackground, modifier = Modifier.size(iconSize))
        }
    }
}

// The website's `.seg` on a touch screen: the choices side by side on the card colour, radius 10, 2 apart; each 44
// high, 12 inside, 13 semibold in textSecondary; the chosen one filled with the text colour. It scrolls sideways when
// it's wider than the page.
@Composable
private fun <T> Seg(choices: List<Pair<T, String>>, chosen: T, label: String, modifier: Modifier = Modifier, choose: (T) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).semantics { contentDescription = label }) {
        Row(Modifier.clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            choices.forEach { (value, words) ->
                val on = value == chosen
                Pressable({ choose(value) }, Modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(7.dp), fill = if (on) scheme.onBackground else Color.Transparent, label = words, selected = on, pressScale = 1f, ring = false) {
                    Box(Modifier.heightIn(min = 44.dp).padding(horizontal = 12.dp), contentAlignment = Alignment.Center) {
                        Text(words, color = if (on) scheme.background else scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                }
            }
        }
    }
}

// MARK: Home

@Composable
private fun MusicHomeTab(nav: Nav, library: Library, head: LazyListScope.() -> Unit, notice: String, seeAll: (MusicTab, String) -> Unit) {
    val api = nav.app.api
    val say = LocalSay.current
    val type = library.type
    val books = type == "audiobooks"
    val pods = type == "podcasts"
    val music = !books && !pods
    val remembered = "music-home-${library.id}"
    var home by remember(library.id) { mutableStateOf(nav.remembered<MusicHome>(remembered)) }
    var failed by remember(library.id) { mutableStateOf(false) }
    var at by rememberSaveable(library.id) { mutableIntStateOf(0) }
    LaunchedEffect(library.id) {
        try {
            val fresh = api.musicHome(library.id)
            nav.remember(remembered, fresh)
            home = fresh
            failed = false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e) && home == null) failed = true
        }
    }
    val h = home
    val hero = h?.hero?.getOrNull(at) ?: h?.hero?.firstOrNull()
    val colour = rememberArtColour(hero?.coverItem?.takeIf { it > 0 }?.let { api.coverUrl(it) })
    val anchor = remember { GlowAnchor() }
    val width = LocalConfiguration.current.screenWidthDp
    val phone = width <= 600

    // An album or book from its tracks: a book at its first unfinished chapter, or the track asked for.
    fun playAlbum(artist: String, title: String, track: Long? = null) {
        nav.app.scope.launch {
            try {
                val tracks = api.tracks(library.id, title, artist)
                if (tracks.isEmpty()) return@launch
                val chosen = if (track != null) tracks.indexOfFirst { it.id == track } else -1
                val from = if (chosen >= 0) chosen else MusicLook.playFrom(type, tracks)
                val keeps = keepsPlace(type)
                nav.startListening(tracks, Start(from, placeOn(tracks[from], keeps)), keeps)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(e.message.orEmpty())
            }
        }
    }

    fun playAll() {
        nav.app.scope.launch {
            try {
                val all = api.musicSongs(library.id, "sort=random&limit=500")
                if (all.isNotEmpty()) nav.startListening(all, Start(0), false)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(e.message.orEmpty())
            }
        }
    }

    val showGlow = h != null && h.hero.isNotEmpty() && !failed
    MusicList(nav, head, notice, Modifier.artGlow(if (showGlow) colour else null, anchor, LocalConfiguration.current.screenHeightDp)) {
        when {
            failed -> item(key = "failed") { MusicEmpty(WebIcons.Audio, "This library wouldn't load", "The server didn't answer. Try again in a moment.") }
            h == null -> albumSkeleton(!books)
            h.hero.isEmpty() -> item(key = "empty") {
                if (pods) PodcastsEmpty(nav) else MusicEmpty(WebIcons.Audio, "Nothing here yet", "Add audio files to this library's folders and scan it.")
            }
            else -> {
                val front = hero ?: h.hero.first()
                item(key = "hero") {
                    GlowGone(anchor)
                    // `.mh-hero`: the cover flow, the name and who, and the buttons, 8 apart and 16 above the rows.
                    Column(
                        Modifier.fillMaxWidth().glowAnchor(anchor).padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        CoverFlow(nav, h.hero, books, at, { at = it }) { nav.push(Route.Album(library.id, it.title, it.artist)) }
                        HeroWords(nav, library.id, front, pods, width.toFloat())
                        FlowRow(
                            Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            if (music) PillButton("Play my music", true, phone) { playAll() }
                            PillButton(if (books) "Play this book" else if (pods) "Play this show" else "Play this album", books || pods, phone) { playAlbum(front.artist, front.title) }
                        }
                    }
                }
                if (h.resume.isNotEmpty()) item(key = "continue") {
                    Shelf("Continue listening") {
                        MhRow { itemsIndexed(h.resume, key = { i, t -> "$i-${t.id}" }) { _, t -> ResumeCard(nav, t) { playAlbum(t.albumArtist.ifEmpty { t.artist }, t.album, t.id) } } }
                    }
                }
                if (!pods && h.artists.isNotEmpty()) item(key = "artists") {
                    Shelf(if (books) "Authors" else "Artists", seeAll = { seeAll(MusicTab.Artists, "") }) {
                        MhRow(if (phone) 12.dp else 20.dp) {
                            itemsIndexed(h.artists, key = { i, a -> "$i-${a.name}" }) { _, a ->
                                ArtistTile(nav, library.id, a, type, Modifier.width(if (phone) 88.dp else (width * 0.12f).coerceIn(110f, 170f).dp))
                            }
                            if (h.counts.artists > h.artists.size || h.artists.size > 4) item(key = "all") { SeeAllTile(true) { seeAll(MusicTab.Artists, "") } }
                        }
                    }
                }
                item(key = "albums") {
                    Shelf(MusicLook.albumShelf(type), h.counts.albums, seeAll = { seeAll(MusicTab.Albums, "") }) {
                        MhRow {
                            itemsIndexed(h.albums, key = { i, a -> "$i-${a.artist}|${a.title}" }) { _, a ->
                                AlbumTile(nav, library.id, a, Modifier.width((width * 0.16f).coerceIn(130f, 200f).dp), book = books)
                            }
                            if (h.counts.albums > h.albums.size) item(key = "all") { SeeAllTile(false) { seeAll(MusicTab.Albums, "") } }
                        }
                    }
                }
                if (music) item(key = "songs") {
                    Shelf("Songs", h.counts.songs, seeAll = { seeAll(MusicTab.Songs, "") }) { SongShelf(nav, h.songs) }
                }
                if (music && MusicVideos.available(nav.libraries)) item(key = "videos") { MusicVideosShelf(nav, library) { seeAll(MusicTab.Videos, "") } }
                if (music && h.recent.isNotEmpty()) item(key = "recent") {
                    Shelf("Played lately", seeAll = { seeAll(MusicTab.Songs, "recent") }) { SongShelf(nav, h.recent) }
                }
            }
        }
    }
}

// Under the cover flow (`.mh-hero-text`): the name in heavy type that opens it, then who (opening them) and the year
// and genre, in the middle, 12 in from the page's sides.
@Composable
private fun HeroWords(nav: Nav, library: Long, album: Album, pods: Boolean, width: Float) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.widthIn(max = 720.dp).padding(horizontal = 12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            album.title.ifEmpty { "Unknown album" }, color = scheme.onBackground, fontSize = MusicLook.heroTitleSize(width).sp, fontWeight = FontWeight.ExtraBold,
            letterSpacing = (-0.022).em, lineHeight = 1.14.em, textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() }.clickable(remember { MutableInteractionSource() }, null) { nav.push(Route.Album(library, album.title, album.artist)) },
        )
        val byArtist = album.artist.isNotEmpty() && !pods
        val rest = listOfNotNull(album.year?.takeIf { it != 0 }?.toString(), album.genre.ifEmpty { null })
        if (byArtist || rest.isNotEmpty()) {
            val words = buildAnnotatedString {
                if (byArtist) {
                    withLink(LinkAnnotation.Clickable("artist", TextLinkStyles(SpanStyle(color = scheme.onBackground, fontWeight = FontWeight.SemiBold))) { nav.push(Route.Artist(library, album.artist)) }) {
                        append(album.artist)
                    }
                }
                rest.forEachIndexed { i, v -> append((if (i > 0 || byArtist) " · " else "") + v) }
            }
            Text(words, color = scheme.onSurfaceVariant, fontSize = 15.sp, lineHeight = BODY_LINE.em, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 2.dp))
        }
    }
}

// The round buttons under the cover flow: "Play my music" in the text colour on the page's, the album's on the card
// colour (a book's and a show's are the strong one). 44 high and 16 inside on a phone, 52 and wider above 600.
@Composable
private fun PillButton(words: String, strong: Boolean, phone: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val ink = if (strong) scheme.background else scheme.onBackground
    Pressable(onClick, Modifier.heightIn(min = if (phone) 44.dp else 52.dp), shape = RoundedCornerShape(50), fill = if (strong) scheme.onBackground else scheme.surfaceVariant, label = words, pressScale = 0.975f, ring = false) {
        Row(
            Modifier.heightIn(min = if (phone) 44.dp else 52.dp).padding(horizontal = if (phone) 16.dp else if (strong) 24.dp else 20.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(WebIcons.Play, null, tint = ink, modifier = Modifier.size(18.dp))
            Text(words, color = ink, fontSize = if (phone) 14.sp else 15.sp, fontWeight = if (strong) FontWeight.Bold else FontWeight.SemiBold, maxLines = 1)
        }
    }
}

// A shelf (`.mh-shelf`): its head, then what's on it, 28 above the next.
@Composable
private fun Shelf(title: String, count: Int? = null, seeAll: (() -> Unit)? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(bottom = 28.dp)) {
        ShelfHead(title, count, seeAll)
        content()
    }
}

// A shelf's head: the name 20 bold, with how many in 13 textHint after it, and "See all ›" in 14 semibold
// textSecondary, 44 to tap, on the same baseline; 12 above what it names.
@Composable
private fun ShelfHead(title: String, count: Int? = null, seeAll: (() -> Unit)? = null) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val locale = pageLocale()
    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        val words = buildAnnotatedString {
            append(title)
            if (count != null) withStyle(SpanStyle(color = extra.hint, fontSize = 13.sp, fontWeight = FontWeight.Medium)) { append(" " + MusicLook.number(count, locale)) }
        }
        Text(words, color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.Bold, lineHeight = 1.14.em, modifier = Modifier.weight(1f).alignByBaseline().semantics { heading() })
        if (seeAll != null) {
            Pressable(seeAll, Modifier.alignByBaseline().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "See all, $title", pressScale = 1f, ring = false) {
                Row(Modifier.heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("See all", color = scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                    Icon(WebIcons.Right, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(18.dp))
                }
            }
        }
    }
}

// A row of a shelf (`.mh-row`): inside the page's 16, sideways, 16 apart, 6 above and 4 below, snapping to a card.
@Composable
private fun MhRow(gap: Dp = 16.dp, content: LazyListScope.() -> Unit) {
    val state = rememberLazyListState()
    LazyRow(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp), state = state, flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Start),
        contentPadding = PaddingValues(start = 2.dp, end = 2.dp, top = 6.dp, bottom = 4.dp), horizontalArrangement = Arrangement.spacedBy(gap),
        verticalAlignment = Alignment.Top, content = content,
    )
}

// "See all" as a tile at the end of a row: 110 square, radius 10 (round for artists), the card colour.
@Composable
private fun SeeAllTile(round: Boolean, onClick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val shape = if (round) CircleShape else RoundedCornerShape(10.dp)
    Pressable(onClick, Modifier.width(110.dp).aspectRatio(1f), shape = shape, fill = scheme.surfaceVariant, label = "See all", pressScale = 1f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text("See all", color = scheme.onBackground, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

// Continue listening (`.mh-resume`): min(340, 84% of the screen) wide on the hover tint, radius 14, 8 inside; the
// cover 110 wide at 3:4, then the album, who, how far, a bar and Resume at the foot.
@Composable
private fun ResumeCard(nav: Nav, t: Item, resume: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val width = minOf(340f, LocalConfiguration.current.screenWidthDp * 0.84f).dp
    val fraction = MusicLook.listened(t)
    Row(
        Modifier.width(width).height(IntrinsicSize.Min).clip(RoundedCornerShape(14.dp)).background(scheme.onBackground.copy(alpha = HOVER)).padding(8.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.width(110.dp).aspectRatio(3f / 4f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
            if (t.poster.isNotEmpty()) WebArt(nav.app.api.posterUrl(t), "", 110.dp, 3f / 4f, Modifier.fillMaxSize(), placeholderless = true)
        }
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(t.album.ifEmpty { t.title }, color = scheme.onBackground, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(t.artist.ifEmpty { t.albumArtist }, color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("${Math.round(fraction * 100)}% listened", color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em)
            Box(Modifier.padding(vertical = 4.dp).fillMaxWidth().height(3.dp).clip(RoundedCornerShape(6.dp)).background(scheme.outline)) {
                Box(Modifier.fillMaxWidth(fraction).fillMaxHeight().background(scheme.primary))
            }
            Spacer(Modifier.weight(1f))
            WebButton("Resume", resume, WebButtonKind.Secondary, WebIcons.Play, small = true)
        }
    }
}

// Songs on a shelf (`.mh-songs`): three to a column on a phone (four wider), each column 84% of the screen, 6 apart
// down and 12 across, sideways.
@Composable
private fun SongShelf(nav: Nav, songs: List<Item>) {
    val width = LocalConfiguration.current.screenWidthDp
    val rows = if (width <= 600) 3 else 4
    val column = if (width <= 600) (width * 0.84f).dp else 280.dp
    val state = rememberLazyListState()
    LazyRow(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp), state = state, flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Start),
        contentPadding = PaddingValues(2.dp), horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        items(songs.indices.chunked(rows), key = { it.first() }) { indices ->
            Column(Modifier.width(column), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                indices.forEach { i -> SongRow(nav, songs[i]) { nav.startListening(songs, Start(i), false) } }
            }
        }
    }
}

// One song as a compact row (`.mh-song`): on the hover tint, the accent's at 14% while it's the one playing; the
// picture 48 (with the playing bars over it), title and who · album, the length, and its "⋯".
@Composable
private fun SongRow(nav: Nav, t: Item, play: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val listening = nav.app.listening
    val on = listening.now?.mediaId == t.id.toString()
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (on) scheme.primary.copy(alpha = 0.14f) else scheme.onBackground.copy(alpha = HOVER)),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Pressable(play, Modifier.weight(1f).heightIn(min = 60.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Play ${t.title}", state = if (on) "Playing" else null, pressScale = 1f, ring = false) {
            Row(
                Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(start = 8.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(48.dp).clip(RoundedCornerShape(6.dp)).background(scheme.surfaceVariant), contentAlignment = Alignment.Center) {
                    if (t.poster.isNotEmpty()) WebArt(nav.app.api.posterUrl(t), "", 64.dp, 1f, Modifier.fillMaxSize(), placeholderless = true)
                    if (on && listening.isPlaying) {
                        Box(Modifier.height(20.dp).clip(RoundedCornerShape(6.dp)).background(SCRIM).padding(4.dp)) { PlayingBars(Color.White) }
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(t.title, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        listOf(t.artist.ifEmpty { t.albumArtist }, t.album).filter { it.isNotEmpty() }.joinToString(" · "), color = scheme.onSurfaceVariant, fontSize = 12.sp,
                        lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(if (t.runtimeSec > 0) clock(t.runtimeSec) else "", color = scheme.onSurfaceVariant, fontSize = 13.sp, style = NUMBERS)
            }
        }
        TrackMenu(nav, t)
    }
}

// The three little bars of what's playing (`.ab-eq`): 3 wide, 2 apart, 12 high, each rising and falling over 0.9 s,
// a third of that apart. Still at 70% when motion is reduced.
@Composable
internal fun PlayingBars(colour: Color) {
    val still = LocalReduceMotion.current
    val beat = rememberInfiniteTransition(label = "bars")
    Row(Modifier.height(12.dp), horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.Bottom) {
        listOf(0, 300, 600).forEach { ahead ->
            val h by beat.animateFloat(
                0.3f, 1f, infiniteRepeatable(tween(450, easing = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)), RepeatMode.Reverse, StartOffset(ahead, StartOffsetType.FastForward)),
                label = "bar",
            )
            Box(Modifier.width(3.dp).fillMaxHeight(if (still) 0.7f else h).clip(RoundedCornerShape(1.dp)).background(colour))
        }
    }
}

// MARK: the cover flow

// Covers in a row with one in front, the others turned away either side, each with its reflection (music/CoverFlow.tsx,
// `.cf` in music.css). A swipe or a tap on a side cover brings it to the front; a tap on the front one opens it. Only
// the three nearest each side are drawn. The row is clipped at the page's sides only.
@Composable
private fun CoverFlow(nav: Nav, covers: List<Album>, tall: Boolean, at: Int, go: (Int) -> Unit, open: (Album) -> Unit) {
    val config = LocalConfiguration.current
    val density = LocalDensity.current
    val phone = config.screenWidthDp <= 600
    val cover = MusicLook.coverSize(config.screenWidthDp.toFloat(), config.screenHeightDp.toFloat(), tall).dp
    val still = LocalReduceMotion.current
    val place by animateFloatAsState(at.toFloat(), if (still) snap() else tween(240, easing = CubicBezierEasing(0.2f, 0.8f, 0.2f, 1f)), label = "covers")
    val sizePx = with(density) { cover.toPx() }
    // The website's perspective of 1200 from the row's middle, which is each cover's own middle before it moves.
    val depth = with(density) { 1200.dp.toPx() }
    fun move(to: Int) = go(to.coerceIn(0, covers.lastIndex))
    Box(
        Modifier.fillMaxWidth().height(cover * 1.2f)
            .drawWithContent { clipRect(0f, -size.height, size.width, size.height * 2) { this@drawWithContent.drawContent() } }
            .pointerInput(covers, at) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    var last = down
                    var taken = false
                    while (true) {
                        val event = awaitPointerEvent(PointerEventPass.Final)
                        val change = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (change.isConsumed) taken = true
                        last = change
                        if (!change.pressed) break
                    }
                    if (taken || last.pressed) return@awaitEachGesture
                    val dx = last.position.x - down.position.x
                    val dy = last.position.y - down.position.y
                    if (abs(dx) > 36.dp.toPx() && abs(dx) > abs(dy)) {
                        move(at + if (dx < 0) 1 else -1)
                    } else if (abs(dx) < viewConfiguration.touchSlop && abs(dy) < viewConfiguration.touchSlop) {
                        // The nearest cover under the finger, front first, where each stands now.
                        val middle = this.size.width / 2f
                        val hit = covers.indices.filter { abs(it - at) <= 3 }.sortedBy { abs(it - at) }.firstOrNull { i ->
                            val spot = MusicLook.coverPlace((i - at).toFloat(), sizePx, phone)
                            val (l, r) = coverSpan(spot, sizePx, depth)
                            down.position.x in (middle + l)..(middle + r)
                        }
                        if (hit == at) open(covers[at]) else if (hit != null) move(hit)
                    }
                }
            }
            .semantics {
                contentDescription = "Covers"
                customActions = listOf(
                    CustomAccessibilityAction("Previous cover") { move(at - 1); true },
                    CustomAccessibilityAction("Next cover") { move(at + 1); true },
                )
            },
    ) {
        covers.forEachIndexed { i, album ->
            if (abs(i - at) > 3) return@forEachIndexed
            key("${album.artist}|${album.title}|$i") {
                val spot = MusicLook.coverPlace(i - place, sizePx, phone)
                val label = "Open ${album.title}${if (album.artist.isNotEmpty()) " by ${album.artist}" else ""}"
                Box(
                    Modifier.align(Alignment.TopCenter).requiredSize(cover, cover * 1.2f).zIndex(5f - abs(i - at))
                        .drawWithContent {
                            val matrix = coverMatrix(spot, this.size.width, this.size.height, depth)
                            drawIntoCanvas { canvas ->
                                val c = canvas.nativeCanvas
                                // As solid as its place says, as one: room for the farthest a cover moves sideways.
                                val w = this.size.width
                                val h = this.size.height
                                if (spot.alpha >= 1f) c.save() else c.saveLayerAlpha(-4 * w, -h, 5 * w, 2 * h, (spot.alpha.coerceAtLeast(0f) * 255).toInt())
                                c.concat(matrix)
                                drawContent()
                                c.restore()
                            }
                        }
                        .then(if (i == at) Modifier.semantics { role = Role.Button; contentDescription = label; onClick { open(album); true } } else Modifier.clearAndSetSemantics { }),
                ) {
                    CoverArt(nav, album, cover)
                }
            }
        }
    }
}

// One cover: square, radius 14, on the card colour with the e-3 shadow; then, 6 under it, its reflection 21.6% of its
// size high, fading from 28% to nothing.
@Composable
private fun CoverArt(nav: Nav, album: Album, size: Dp) {
    val scheme = MaterialTheme.colorScheme
    val url = album.coverItem.takeIf { it > 0 }?.let { nav.app.api.coverUrl(it) }
    // The reflection hangs a little below the cover's own box, as the website's does.
    Column(Modifier.wrapContentHeight(Alignment.Top, unbounded = true).width(size)) {
        Box(Modifier.size(size).cssShadow(10.dp, 30.dp, E3, 14.dp).clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant)) {
            if (url != null) WebArt(url, "", size, 1f, Modifier.fillMaxSize(), placeholderless = true)
            else Placeholder(album.title.ifEmpty { "Unknown" }, Modifier.fillMaxSize(), centred = false)
        }
        if (url != null) {
            Box(
                Modifier.padding(top = 6.dp).width(size).height(size * 0.216f).clip(RoundedCornerShape(topStart = 14.dp, topEnd = 14.dp))
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.28f), Color.Transparent)), blendMode = BlendMode.DstIn)
                    },
            ) {
                Box(Modifier.wrapContentHeight(Alignment.Top, unbounded = true).requiredSize(size).graphicsLayer { scaleY = -1f }) {
                    WebArt(url, "", size, 1f, Modifier.fillMaxSize(), placeholderless = true)
                }
            }
        }
    }
}

// CSS's translateX, rotateY and scale about the cover's middle, seen with a perspective from the same point, as one
// matrix for the canvas: the cover's plane projected.
private fun coverMatrix(spot: MusicLook.CoverPlace, width: Float, height: Float, depth: Float): android.graphics.Matrix {
    val turn = Math.toRadians(spot.turn.toDouble())
    val m = android.graphics.Matrix()
    m.setValues(
        floatArrayOf(
            spot.scale * cos(turn).toFloat(), 0f, spot.x,
            0f, spot.scale, 0f,
            spot.scale * sin(turn).toFloat() / depth, 0f, 1f,
        ),
    )
    m.preTranslate(-width / 2, -height / 2)
    m.postTranslate(width / 2, height / 2)
    return m
}

// Where a cover's left and right edges land, from the row's middle, for finding which one was tapped.
private fun coverSpan(spot: MusicLook.CoverPlace, size: Float, depth: Float): Pair<Float, Float> {
    val turn = Math.toRadians(spot.turn.toDouble())
    fun x(u: Float) = (spot.scale * cos(turn).toFloat() * u + spot.x) / (1 + spot.scale * sin(turn).toFloat() * u / depth)
    val a = x(-size / 2)
    val b = x(size / 2)
    return minOf(a, b) to maxOf(a, b)
}

// MARK: cards

// An album's, book's or podcast's card (`.album-card`): the cover square (2:3 for a book), radius 10, the e-1 shadow;
// the name 14 semibold on two lines 8 under it, then who and when in 12 textHint.
@Composable
private fun AlbumTile(nav: Nav, library: Long, album: Album, modifier: Modifier = Modifier, book: Boolean = false, noArtist: Boolean = false) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val sub = listOf(if (noArtist) "" else album.artist, album.year?.takeIf { it != 0 }?.toString().orEmpty()).filter { it.isNotEmpty() }.joinToString(" · ")
    val title = album.title.ifEmpty { "Unknown album" }
    Pressable(
        { nav.push(Route.Album(library, album.title, album.artist)) }, modifier, shape = RoundedCornerShape(10.dp), fill = Color.Transparent,
        label = listOf(title, sub).filter { it.isNotEmpty() }.joinToString(", "), pressScale = 1f, ring = false, clip = false,
    ) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(if (book) 2f / 3f else 1f).restingShadow(10.dp).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
                if (album.coverItem > 0) WebArt(nav.app.api.coverUrl(album.coverItem), "", 160.dp, if (book) 2f / 3f else 1f, Modifier.fillMaxSize(), placeholderless = true)
                else Placeholder(album.title.ifEmpty { "Unknown" }, Modifier.fillMaxSize(), centred = false)
            }
            Text(title, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 8.dp))
            Text(sub, color = extra.hint, fontSize = 12.sp, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

// An artist's or author's tile (`.mh-artist`): the round picture, the name 14 semibold; how many only on a screen
// wider than a phone.
@Composable
private fun ArtistTile(nav: Nav, library: Long, artist: Artist, libraryType: String, modifier: Modifier = Modifier) {
    val scheme = MaterialTheme.colorScheme
    val wide = LocalConfiguration.current.screenWidthDp > 600
    val name = artist.name.ifEmpty { "Unknown" }
    Pressable({ nav.push(Route.Artist(library, artist.name)) }, modifier, shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = name, pressScale = 1f, ring = false, clip = false) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            ArtistPhoto(nav, library, artist.name, false, Modifier.fillMaxWidth())
            Text(name, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (wide) Text(MusicLook.artistTileCount(artist.albums, libraryType), color = LocalExtraColours.current.hint, fontSize = 12.sp, lineHeight = BODY_LINE.em, maxLines = 1)
        }
    }
}

// The round picture: the card colour with the initial in textHint behind it, while it comes or when there's none.
@Composable
private fun ArtistPhoto(nav: Nav, library: Long, name: String, big: Boolean, modifier: Modifier) {
    val scheme = MaterialTheme.colorScheme
    val width = LocalConfiguration.current.screenWidthDp.toFloat()
    val initial = if (big) (width * 0.06f).coerceIn(48f, 80f) else (width * 0.04f).coerceIn(32f, 48f)
    Box(
        modifier.aspectRatio(1f).then(if (big) Modifier.cssShadow(10.dp, 30.dp, E3, 999.dp) else Modifier.cssShadow(10.dp, 24.dp, Color(0x80000000), 999.dp))
            .clip(CircleShape).background(scheme.surfaceVariant),
        contentAlignment = Alignment.Center,
    ) {
        Text(name.ifEmpty { "?" }.take(1), color = LocalExtraColours.current.hint, fontSize = initial.sp, fontWeight = FontWeight.Bold)
        WebArt(nav.app.api.artistPhotoUrl(library, name), "", if (big) 200.dp else 130.dp, 1f, Modifier.fillMaxSize(), placeholderless = true)
    }
}

// MARK: the other parts of a library

@Composable
private fun AlbumsTab(nav: Nav, library: Library, sort: String, desc: Boolean, genre: String, setGenre: (String) -> Unit, head: LazyListScope.() -> Unit, notice: String) {
    val api = nav.app.api
    val type = library.type
    val books = type == "audiobooks"
    val pods = type == "podcasts"
    var albums by remember(library.id, sort, genre) { mutableStateOf<List<Album>?>(null) }
    var genres by remember(library.id) { mutableStateOf(emptyList<String>()) }
    var picking by remember { mutableStateOf(false) }
    LaunchedEffect(library.id, sort, genre) { albums = runCatching { api.albums(library.id, sort, null, genre) }.getOrDefault(emptyList()) }
    LaunchedEffect(library.id) { if (!pods) genres = runCatching { api.genres(library.id) }.getOrDefault(emptyList()) }
    val list = albums
    val columns = MusicLook.columns(LocalConfiguration.current.screenWidthDp - 32f, 104f, 16f)
    MusicList(nav, head, notice) {
        item(key = "filters") {
            CountAndSelect(list?.let { MusicLook.albumsCount(it.size, type) }, if (genres.isEmpty()) null else genre.ifEmpty { "All genres" }) { picking = true }
        }
        when {
            list == null -> albumSkeleton(!books)
            list.isEmpty() -> item(key = "empty") {
                if (pods) PodcastsEmpty(nav)
                else MusicEmpty(WebIcons.Audio, "Nothing here", if (genre.isNotEmpty()) "Nothing in this genre." else "Add audio files to this library's folders and scan it.")
            }
            else -> gridRows("album", MusicLook.shownAlbums(list, sort, desc), columns) { a -> AlbumTile(nav, library.id, a, Modifier.fillMaxWidth(), book = books) }
        }
    }
    if (picking) ChoiceSheet("Genre", listOf("" to "All genres") + genres.map { it to it }, genre, setGenre) { picking = false }
}

@Composable
private fun ArtistsTab(nav: Nav, library: Library, sort: String, desc: Boolean, head: LazyListScope.() -> Unit, notice: String) {
    val api = nav.app.api
    val type = library.type
    var artists by remember(library.id) { mutableStateOf<List<Artist>?>(null) }
    var words by rememberSaveable(library.id) { mutableStateOf("") }
    LaunchedEffect(library.id) { artists = runCatching { api.artists(library.id) }.getOrDefault(emptyList()) }
    val locale = pageLocale()
    val all = artists
    val width = LocalConfiguration.current.screenWidthDp - 32f
    MusicList(nav, head, notice) {
        item(key = "filters") {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (all != null) Text(MusicLook.artistsCount(all.size, type), color = MaterialTheme.colorScheme.onBackground, fontSize = 15.sp, lineHeight = BODY_LINE.em)
                WebInput(words, { words = it }, if (type == "audiobooks") "Find an author…" else "Find an artist…", Modifier.fillMaxWidth())
            }
        }
        if (all == null) albumSkeleton(true)
        else gridRows("artist", MusicLook.shownArtists(all, words, sort, desc, locale), MusicLook.columns(width, 130f, 16f)) { a ->
            ArtistTile(nav, library.id, a, type, Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun SongsTab(
    nav: Nav, library: Library, view: String, setView: (String) -> Unit, sort: String, desc: Boolean, genre: String, setGenre: (String) -> Unit,
    head: LazyListScope.() -> Unit, notice: String,
) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    var words by rememberSaveable(library.id) { mutableStateOf("") }
    var search by remember { mutableStateOf(words.trim()) }
    var songs by remember(library.id, view, sort, desc, genre, search) { mutableStateOf<List<Item>?>(null) }
    var genres by remember(library.id) { mutableStateOf(emptyList<String>()) }
    var picking by remember { mutableStateOf(false) }
    // A quarter of a second after the last letter.
    LaunchedEffect(words) {
        delay(250)
        search = words.trim()
    }
    LaunchedEffect(library.id, view, sort, desc, genre, search) {
        songs = runCatching { api.musicSongs(library.id, MusicLook.songsQuery(view, sort, desc, genre, search)) }.getOrDefault(emptyList())
    }
    LaunchedEffect(library.id) { genres = runCatching { api.genres(library.id) }.getOrDefault(emptyList()) }
    val locale = pageLocale()
    val list = songs
    MusicList(nav, head, notice) {
        item(key = "views") { Seg(MusicLook.songViews, view, "Which songs", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 12.dp), setView) }
        item(key = "filters") {
            // `.mh-filters` on a phone: how many with Play and Shuffle, then Find and the genre each across the page.
            Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (list != null) {
                        Box(Modifier.heightIn(min = 44.dp), contentAlignment = Alignment.CenterStart) {
                            Text(MusicLook.songsCount(list, locale), color = scheme.onBackground, fontSize = 15.sp, lineHeight = BODY_LINE.em)
                        }
                    }
                    val some = !list.isNullOrEmpty()
                    WebButton("Play", { list?.let { nav.startListening(it, Start(0), false) } }, WebButtonKind.Primary, WebIcons.Play, small = true, enabled = some)
                    WebButton("Shuffle", { list?.let { nav.startListening(it.shuffled(), Start(0), false) } }, WebButtonKind.Secondary, small = true, enabled = some)
                }
                WebInput(words, { words = it }, "Find a song…", Modifier.fillMaxWidth())
                if (genres.isNotEmpty()) Select(genre.ifEmpty { "All genres" }, "Genre", Modifier.fillMaxWidth(), fill = true) { picking = true }
            }
        }
        when {
            list == null -> item(key = "loading") { MusicSpinner() }
            list.isEmpty() -> item(key = "empty") {
                val (title, text) = MusicLook.emptySongs(view, search.isNotEmpty() || genre.isNotEmpty())
                MusicEmpty(WebIcons.Audio, title, text)
            }
            else -> trackRows(nav, "song", list, showAlbum = true) { i -> nav.startListening(list, Start(i), false) }
        }
    }
    if (picking) ChoiceSheet("Genre", listOf("" to "All genres") + genres.map { it to it }, genre, setGenre) { picking = false }
}

@Composable
private fun PlaylistsTab(nav: Nav, library: Library, head: LazyListScope.() -> Unit, notice: String, openSongs: (String) -> Unit) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val say = LocalSay.current
    var lists by remember { mutableStateOf<List<Collection>?>(null) }
    LaunchedEffect(Unit) { lists = runCatching { api.collections() }.getOrDefault(emptyList()) }

    fun playView(view: String) {
        nav.app.scope.launch {
            try {
                val items = api.musicSongs(library.id, "view=$view&limit=500")
                if (items.isEmpty()) say("Nothing there yet") else nav.startListening(items, Start(0), false)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(e.message.orEmpty())
            }
        }
    }
    MusicList(nav, head, notice) {
        item(key = "built") {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                MusicLook.built.forEach { b ->
                    ListCard {
                        Column(
                            Modifier.weight(1f).clickable(remember { MutableInteractionSource() }, null, role = Role.Button) { openSongs(b.view) }.semantics { contentDescription = "${b.name}, ${b.about}" },
                        ) {
                            Text(b.name, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(b.about, color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        }
                        RoundIcon(WebIcons.Play, 20.dp, scheme.onPrimary, "Play ${b.name}", scheme.primary) { playView(b.view) }
                    }
                }
            }
        }
        item(key = "yours") {
            Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("Your playlists", color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.Bold, lineHeight = 1.14.em, modifier = Modifier.weight(1f).alignByBaseline().semantics { heading() })
                Pressable({ nav.push(Route.Page("/collections", "Collections")) }, Modifier.alignByBaseline().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Make one, or a smart one", pressScale = 1f, ring = false) {
                    Box(Modifier.heightIn(min = 44.dp), contentAlignment = Alignment.Center) {
                        Text("Make one, or a smart one", color = scheme.onSurfaceVariant, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    }
                }
            }
        }
        val all = lists
        when {
            all == null -> item(key = "loading") { MusicSpinner() }
            all.isEmpty() -> item(key = "none") {
                Text(
                    "None yet. Add any song to a playlist from its menu, or make a smart one in Collections that keeps itself up to date.",
                    color = extra.hint, fontSize = 15.sp, lineHeight = BODY_LINE.em, modifier = Modifier.padding(horizontal = 16.dp),
                )
            }
            else -> item(key = "lists") {
                Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    all.filter { it.system.isEmpty() }.forEach { c ->
                        val words = if (c.kind == "smart") "Smart playlist" else MusicLook.count(c.count, "item", "items")
                        Pressable({ nav.push(Route.Page("/collections/${c.id}", c.name)) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "${c.name}, $words", pressScale = 1f, ring = false) {
                            ListCard {
                                Box(Modifier.size(52.dp).clip(RoundedCornerShape(6.dp)).background(scheme.surfaceVariant)) {
                                    if (c.coverId > 0) WebArt(api.coverUrl(c.coverId), "", 96.dp, 1f, Modifier.fillMaxSize(), placeholderless = true)
                                }
                                Column(Modifier.weight(1f)) {
                                    Text(c.name, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(words, color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// A list's card (`.mh-list`): at least 68 high, 8 inside and apart, radius 10, on the hover tint.
@Composable
private fun ListCard(content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 68.dp).clip(RoundedCornerShape(10.dp)).background(MaterialTheme.colorScheme.onBackground.copy(alpha = HOVER)).padding(8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = content,
    )
}

// The Albums tab's line: how many, then the genre at 40% of the line taking half of what's left (the gap before it
// has the other half), or on a line of its own when they don't fit.
@Composable
private fun CountAndSelect(count: String?, genre: String?, pick: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Layout(
        content = {
            if (count != null) Text(count, color = scheme.onBackground, fontSize = 15.sp, lineHeight = BODY_LINE.em)
            if (genre != null) Select(genre, "Genre", Modifier.fillMaxWidth(), fill = true, open = pick)
        },
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
    ) { parts, constraints ->
        val gap = 8.dp.roundToPx()
        val w = constraints.maxWidth
        val counted = if (count != null) parts[0].measure(Constraints(maxWidth = w)) else null
        val select = if (genre != null) parts.last() else null
        val basis = (w * 0.4f).toInt()
        val used = (counted?.width?.plus(gap) ?: 0) + gap
        val fits = used + basis <= w
        val selectWidth = if (fits) basis + (w - used - basis) / 2 else w
        val chosen = select?.measure(Constraints.fixedWidth(selectWidth))
        val line = maxOf(counted?.height ?: 0, if (fits) chosen?.height ?: 0 else 0)
        val height = line + if (!fits && chosen != null) (if (counted != null) gap else 0) + chosen.height else 0
        layout(w, height) {
            counted?.place(0, (line - counted.height) / 2)
            if (chosen != null) {
                if (fits) chosen.place(w - chosen.width, (line - chosen.height) / 2)
                else chosen.place(0, if (counted != null) line + gap else 0)
            }
        }
    }
}

// The website's select on a phone: 44 high, the card colour, the control colour's outline, radius 10, 14 words, and
// its small triangle 10 from the right. It opens a sheet of the choices.
@Composable
private fun Select(words: String, label: String, modifier: Modifier = Modifier, fill: Boolean = false, open: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    Pressable(open, modifier.heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = scheme.surfaceVariant, label = "$label, $words", pressScale = 1f, ring = false) {
        Box(Modifier.then(if (fill) Modifier.fillMaxWidth() else Modifier).heightIn(min = 44.dp).border(1.dp, extra.control, RoundedCornerShape(10.dp))) {
            Text(
                words, color = scheme.onBackground, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.align(Alignment.CenterStart).padding(start = 12.dp, end = 32.dp),
            )
            val ink = scheme.onSurfaceVariant
            Canvas(Modifier.align(Alignment.CenterEnd).padding(end = 10.dp).size(10.dp, 5.dp)) {
                drawPath(Path().apply { moveTo(0f, 0f); lineTo(size.width, 0f); lineTo(size.width / 2, size.height); close() }, ink)
            }
        }
    }
}

// A select's choices, as a sheet of rows with the chosen one ticked.
@Composable
private fun ChoiceSheet(title: String, choices: List<Pair<String, String>>, chosen: String, choose: (String) -> Unit, close: () -> Unit) {
    WebSheet(title, close) {
        SheetRows(choices.map { (value, words) -> SheetRow(words, if (value == chosen) WebIcons.Check else null) { choose(value) } }, close)
    }
}

// A grid of `repeat(auto-fill, minmax(…, 1fr))` as rows of the list: 16 apart across and 24 down.
private fun <T> LazyListScope.gridRows(prefix: String, all: List<T>, columns: Int, bottom: Dp = 0.dp, cell: @Composable (T) -> Unit) {
    val rows = all.chunked(columns)
    itemsIndexed(rows, key = { i, _ -> "$prefix-$i" }) { i, row ->
        Row(
            Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = if (i > 0) 24.dp else 0.dp, bottom = if (i == rows.lastIndex) bottom else 0.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            row.forEach { Box(Modifier.weight(1f)) { cell(it) } }
            repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
        }
    }
}

// Grey shapes where a grid of covers will land, square or a book's 2:3.
private fun LazyListScope.albumSkeleton(square: Boolean) {
    item(key = "skeleton") {
        val columns = MusicLook.columns(LocalConfiguration.current.screenWidthDp - 32f, 104f, 16f)
        Column(Modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            repeat((12 + columns - 1) / columns) { r ->
                Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                    repeat(columns) { c ->
                        if (r * columns + c < 12) Skel(Modifier.weight(1f).aspectRatio(if (square) 1f else 2f / 3f), 10.dp) else Spacer(Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

// The website's EmptyState: in the middle, 64 above and below, a 56 circle of the card colour with the 26 icon in
// textHint, the title 17, the words 14 in textSecondary.
@Composable
private fun MusicEmpty(icon: ImageVector, title: String, words: String) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(vertical = 64.dp, horizontal = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.padding(bottom = 16.dp).size(56.dp).clip(CircleShape).background(scheme.surfaceVariant), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = LocalExtraColours.current.hint, modifier = Modifier.size(26.dp))
        }
        Text(title, color = scheme.onBackground, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 4.dp).semantics { heading() })
        if (words.isNotEmpty()) Text(words, color = scheme.onSurfaceVariant, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 360.dp).padding(bottom = 16.dp))
    }
}

// A podcast library with nothing followed yet.
@Composable
private fun PodcastsEmpty(nav: Nav) {
    MusicEmpty(
        WebIcons.Mic, "Your podcasts will live here",
        if (nav.me?.isAdmin == true) "Follow a podcast from this library's ⋯." else "Ask whoever runs this server to follow some shows.",
    )
}

// The website's spinner (`.loading-box`): 28 across, a 3-wide ring in the raised colour with its top quarter in the
// accent, turning every 0.8 s, 64 from everything.
@Composable
private fun MusicSpinner() {
    val raised = LocalExtraColours.current.raised
    val accent = MaterialTheme.colorScheme.primary
    val turn by rememberInfiniteTransition(label = "spin").animateFloat(0f, 360f, infiniteRepeatable(tween(800, easing = LinearEasing), RepeatMode.Restart), label = "turn")
    Box(Modifier.fillMaxWidth().padding(64.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(28.dp).semantics { contentDescription = "Loading" }) {
            val w = 3.dp.toPx()
            val box = Size(size.width - w, size.height - w)
            drawArc(raised, 0f, 360f, false, topLeft = Offset(w / 2, w / 2), size = box, style = Stroke(w))
            drawArc(accent, 225f + turn, 90f, false, topLeft = Offset(w / 2, w / 2), size = box, style = Stroke(w))
        }
    }
}

// MARK: tracks

// The website's track list (`.track-list`): each row its number (or the playing bars), the title with who and album,
// the length; a heart and "⋯" beside it for songs; a heading where the disc changes when there are several.
private fun LazyListScope.trackRows(
    nav: Nav, prefix: String, tracks: List<Item>, showAlbum: Boolean = false, episodes: Boolean = false, discs: Boolean = false,
    hearts: Boolean = !episodes, play: (Int) -> Unit,
) {
    fun disc(t: Item) = t.discNo?.takeIf { it != 0 } ?: 1
    val manyDiscs = discs && tracks.map(::disc).distinct().size > 1
    itemsIndexed(tracks, key = { i, t -> "$prefix-$i-${t.id}" }) { i, t ->
        val newDisc = manyDiscs && (i == 0 || disc(tracks[i - 1]) != disc(t))
        TrackRow(nav, t, i, if (newDisc) disc(t) else null, showAlbum, episodes, hearts, play)
    }
}

@Composable
private fun TrackRow(nav: Nav, t: Item, at: Int, newDisc: Int?, showAlbum: Boolean, episodes: Boolean, hearts: Boolean, play: (Int) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val listening = nav.app.listening
    val say = LocalSay.current
    val on = listening.now?.mediaId == t.id.toString()
    val liked = listening.liked[t.id] == true
    val fraction = MusicLook.listened(t)
    val line = scheme.outline
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp)) {
        if (newDisc != null) {
            Text(
                "DISC $newDisc", color = scheme.onSurfaceVariant, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.07.em,
                modifier = Modifier.padding(start = 8.dp, end = 8.dp, top = 16.dp, bottom = 4.dp).semantics { heading() },
            )
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Pressable(
                { play(at) },
                // A hairline just above every row but the first, the width of the row's button.
                Modifier.weight(1f).heightIn(min = 52.dp).drawBehind { if (at > 0) drawRect(line, Offset(0f, -1.dp.toPx()), Size(size.width, 1.dp.toPx())) },
                shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = "Play ${t.title}", state = if (on) "Playing" else null, pressScale = 1f, ring = false,
            ) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Box(Modifier.width(32.dp), contentAlignment = Alignment.Center) {
                        if (on && listening.isPlaying) PlayingBars(extra.accentText)
                        else Text(if (episodes) "" else "${t.track ?: (at + 1)}", color = extra.hint, fontSize = 13.sp, style = NUMBERS)
                    }
                    Column(
                        Modifier.weight(1f).drawBehind {
                            // How far into it, 2 high in the accent, 4 under the words.
                            if (fraction > 0f) drawRoundRect(
                                scheme.primary, Offset(0f, size.height + 2.dp.toPx()), Size(size.width * fraction, 2.dp.toPx()), CornerRadius(4.dp.toPx()),
                            )
                        },
                    ) {
                        Text(t.title, color = if (on) extra.accentText else scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.Medium, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        val under = when {
                            showAlbum -> listOf(t.artist, t.album).filter { it.isNotEmpty() }.joinToString(" · ")
                            episodes -> MusicLook.episodeLine(t)
                            else -> null
                        }
                        if (!under.isNullOrEmpty()) Text(under, color = extra.hint, fontSize = 12.sp, fontWeight = FontWeight.Medium, lineHeight = BODY_LINE.em, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (t.progress?.watched == true) Icon(WebIcons.Check, "Finished", tint = extra.hint, modifier = Modifier.size(14.dp))
                        Text(if (t.runtimeSec > 0) clock(t.runtimeSec) else "", color = extra.hint, fontSize = 13.sp, style = NUMBERS)
                    }
                }
            }
            if (hearts) {
                RoundIcon(
                    if (liked) WebIcons.HeartOn else WebIcons.Heart, 18.dp, if (liked) extra.accentText else extra.hint,
                    if (liked) "Remove ${t.title} from liked songs" else "Like ${t.title}",
                ) { listening.toggleLike(t.id, say) }
                TrackMenu(nav, t)
            }
        }
    }
}

// The website's round icon button (`.mp-ibtn`): 44 across, its icon in the middle; pressed, 0.94.
@Composable
private fun RoundIcon(icon: ImageVector, iconSize: Dp, tint: Color, label: String, fill: Color = Color.Transparent, onClick: () -> Unit) {
    Pressable(onClick, Modifier.size(44.dp), shape = CircleShape, fill = fill, label = label, pressScale = 0.94f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(icon, null, tint = tint, modifier = Modifier.size(iconSize)) }
    }
}

// A song's other actions, in one place on every list (music/parts.tsx TrackMenu): play next, add to the queue, like,
// a station, a playlist, the artist and the album.
@Composable
private fun TrackMenu(nav: Nav, t: Item) {
    val listening = nav.app.listening
    val say = LocalSay.current
    var open by remember { mutableStateOf(false) }
    var adding by remember { mutableStateOf(false) }
    val close = { open = false; adding = false }
    Box {
        RoundIcon(WebIcons.AudioMore, 20.dp, MaterialTheme.colorScheme.onSurfaceVariant, "More for ${t.title}") { open = !open; adding = false }
        if (open) PopPanel(close) {
            if (adding) {
                PlaylistPicker(nav, listOf(t), close)
            } else {
                val liked = listening.liked[t.id] == true
                PopItem("Play next", WebIcons.Play) { listening.playNext(listOf(t), false); say("Plays next"); close() }
                PopItem("Add to the queue", WebIcons.Plus) { listening.addToQueue(listOf(t), false); say("Added to the queue"); close() }
                PopItem(if (liked) "Liked" else "Like", if (liked) WebIcons.HeartOn else WebIcons.Heart) { listening.toggleLike(t.id, say); close() }
                PopItem("Start a station from this", WebIcons.Station) { nav.startStation(t, say); close() }
                PopItem("Add to a playlist…", WebIcons.AddList) { adding = true }
                val artist = t.albumArtist.ifEmpty { t.artist }
                if (t.artist.isNotEmpty()) PopItem("Go to artist", null) { close(); nav.push(Route.Artist(t.libraryId, artist)) }
                if (t.album.isNotEmpty()) PopItem("Go to album", null) { close(); nav.push(Route.Album(t.libraryId, t.album, artist)) }
            }
        }
    }
}

// A station from a song (the website's startRadio): two songs at least, or it says why not.
private fun Nav.startStation(track: Item, say: (String) -> Unit) {
    app.scope.launch {
        try {
            val songs = app.api.songRadio(track.id)
            if (songs.size < 2) say("There isn't enough here yet to make a station from this song") else startListening(songs, Start(0), false)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            say(e.message.orEmpty())
        }
    }
}

// Add to a playlist (audio/controls.tsx PlaylistPicker): New playlist, then each of this person's own; a new one is
// named in a field and made with "Make it".
@Composable
internal fun PlaylistPicker(nav: Nav, items: List<Item>, done: () -> Unit) {
    val api = nav.app.api
    val say = LocalSay.current
    var lists by remember { mutableStateOf<List<Collection>?>(null) }
    var making by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { lists = runCatching { api.collections().filter { it.kind == "manual" && it.system.isEmpty() } }.getOrDefault(emptyList()) }

    suspend fun add(id: Long, called: String) {
        busy = true
        try {
            api.addToCollection(id, CollectionItems(items.map { it.id }))
            say("Added to $called")
            done()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            say(e.message.orEmpty())
        }
        busy = false
    }

    fun make() {
        val n = name.trim()
        if (n.isEmpty() || busy) return
        busy = true
        nav.app.scope.launch {
            try {
                add(api.newCollection(n).id, n)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                say(e.message.orEmpty())
                busy = false
            }
        }
    }
    if (making) {
        val focus = remember { FocusRequester() }
        LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
        Column(Modifier.width(240.dp).padding(6.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            WebInput(name, { name = it.take(120) }, "Name", Modifier.fillMaxWidth(), focus = focus) { make() }
            WebButton("Make it", { make() }, WebButtonKind.Primary, small = true, enabled = !busy && name.isNotBlank())
        }
        return
    }
    PopItem("New playlist", WebIcons.Plus) { making = true }
    if (lists == null) Text("Loading…", color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 12.sp, modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp))
    lists?.forEach { c -> PopItem(c.name, null, enabled = !busy) { nav.app.scope.launch { add(c.id, c.name) } } }
}

// The website's pop-over (audio/controls.tsx Pop, `.mp-pop-body`): under its button, or over it when there's no room
// below, its right edge at the button's and 8 from the screen's edges; the panel colour, a hairline, radius 14, 6
// inside, at least 220 wide, rows 1 apart.
@Composable
internal fun PopPanel(close: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val density = LocalDensity.current
    val config = LocalConfiguration.current
    val shade = with(density) { SHADE_ROOM.roundToPx() }
    val place = remember(shade) { PopPlace(with(density) { 8.dp.roundToPx() }, shade) }
    Popup(popupPositionProvider = place, onDismissRequest = close, properties = PopupProperties(focusable = true)) {
        // Room round the panel for its shadow; a tap there closes it, as one outside it does.
        Box(Modifier.clickable(remember { MutableInteractionSource() }, null, onClick = close).padding(SHADE_ROOM)) {
            Column(
                Modifier.width(IntrinsicSize.Max).widthIn(min = 220.dp, max = (config.screenWidthDp - 16).dp)
                    .heightIn(max = minOf(config.screenHeightDp * 0.6f, 460f).dp)
                    .cssShadow(10.dp, 30.dp, E3, 14.dp).clip(RoundedCornerShape(14.dp)).background(scheme.surface)
                    .border(1.dp, scheme.outline, RoundedCornerShape(14.dp))
                    .clickable(remember { MutableInteractionSource() }, null) {}
                    .verticalScroll(rememberScrollState()).padding(6.dp),
                verticalArrangement = Arrangement.spacedBy(1.dp), content = content,
            )
        }
    }
}

private val SHADE_ROOM = 16.dp

private class PopPlace(private val room: Int, private val shade: Int) : PopupPositionProvider {
    override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
        val w = popupContentSize.width - 2 * shade
        val h = popupContentSize.height - 2 * shade
        val left = maxOf(room, minOf(windowSize.width - w - room, anchorBounds.right - w))
        val below = anchorBounds.bottom + room
        val above = anchorBounds.top - h - room
        val top = if (below + h <= windowSize.height - room) below else maxOf(room, above)
        return IntOffset(left - shade, top - shade)
    }
}

// A row of a pop-over: 44 high, 12 inside, an 18 icon 10 before the words in 14.
@Composable
private fun PopItem(words: String, icon: ImageVector?, enabled: Boolean = true, run: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Pressable(run, Modifier.fillMaxWidth().heightIn(min = 44.dp), shape = RoundedCornerShape(10.dp), fill = Color.Transparent, label = words, enabled = enabled, pressScale = 1f, disabledAlpha = 0.45f, ring = false) {
        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (icon != null) Icon(icon, null, tint = scheme.onSurface, modifier = Modifier.size(18.dp))
            Text(words, color = scheme.onSurface, fontSize = 14.sp, maxLines = 1)
        }
    }
}

// MARK: an album, a book or a podcast

@Composable
private fun AlbumPage(nav: Nav, route: Route.Album) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val listening = nav.app.listening
    var library by remember(route.library) { mutableStateOf<Library?>(null) }
    var tracks by remember(route.key) { mutableStateOf<List<Item>?>(null) }
    var others by remember(route.key) { mutableStateOf<List<Album>>(emptyList()) }
    var gone by remember(route.key) { mutableStateOf<Set<Long>>(emptySet()) }
    var toast by remember { mutableStateOf("") }
    val say: (String) -> Unit = { toast = it }
    // The kind of library first: Play means something different in a book.
    LaunchedEffect(route.key) {
        library = runCatching { api.libraries().firstOrNull { it.id == route.library } }.getOrNull()
        tracks = try {
            api.tracks(route.library, route.album, route.artist)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (nav.handleExpired(e)) return@LaunchedEffect
            emptyList()
        }
    }
    // The same artist's other albums: other versions of this one, and the rest.
    LaunchedEffect(route.key) {
        if (route.artist.isNotEmpty()) others = runCatching { api.albums(route.library, "year", route.artist).filter { it.title != route.album } }.getOrDefault(emptyList())
    }
    val discs = tracks.orEmpty().mapNotNull { it.cdDisc?.takeIf { d -> d > 0 } }.distinct()
    // A disc whose image has gone isn't offered to insert.
    LaunchedEffect(discs) { discs.forEach { d -> if (api.discGone(d)) gone = gone + d } }
    val type = library?.type.orEmpty()
    LaunchedEffect(type) { if (type == "music") listening.loadLikes(route.library) }
    val coverId = tracks?.firstOrNull { it.poster.isNotEmpty() }?.id
    val colour = rememberArtColour(coverId?.let { api.coverUrl(it) })
    val anchor = remember { GlowAnchor() }
    val state = rememberLazyListState()
    TracksScroll(state)
    val list = tracks
    if (list == null) {
        Box(Modifier.fillMaxSize().padding(top = LocalTopRoom.current)) { MusicSpinner() }
        return
    }
    val mode = MusicLook.mode(type)
    val books = mode != "music"
    val pods = mode == "podcasts"
    val keeps = keepsPlace(type)
    fun playTrack(i: Int) {
        val t = list[i]
        val disc = t.cdDisc?.takeIf { it > 0 }
        if (disc != null) nav.push(Route.Page("/cd/$disc?play=1&track=${t.track ?: 1}"))
        else nav.startListening(list, Start(i, placeOn(t, keeps)), keeps)
    }
    val base = MusicLook.baseTitle(route.album)
    val versions = others.filter { MusicLook.baseTitle(it.title) == base }
    val more = others.filter { MusicLook.baseTitle(it.title) != base }
    val allLiked = list.isNotEmpty() && list.all { listening.liked[it.id] == true }
    val width = LocalConfiguration.current.screenWidthDp.toFloat()
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalSay provides say) {
            LazyColumn(
                Modifier.fillMaxSize().artGlow(colour, anchor, LocalConfiguration.current.screenHeightDp), state = state,
                contentPadding = PaddingValues(top = LocalTopRoom.current, bottom = LocalBottomRoom.current),
            ) {
                item(key = "head") {
                    GlowGone(anchor)
                    Column(Modifier.fillMaxWidth().glowAnchor(anchor).padding(horizontal = 16.dp)) {
                        TitleBackLink(library?.name ?: if (books) "Audiobooks" else "Music", Modifier.padding(top = 4.dp, bottom = 12.dp)) { nav.openLibraryPage(route.library) }
                        // `.album-head` on a phone: the cover, then 20 under it what it is, its name, who, the facts and the buttons.
                        Column(Modifier.padding(top = 8.dp, bottom = 24.dp)) {
                            Box(
                                Modifier.width(minOf(width * 0.6f, 240f).dp).aspectRatio(if (books) 2f / 3f else 1f).cssShadow(10.dp, 30.dp, E3, 14.dp)
                                    .clip(RoundedCornerShape(14.dp)).background(scheme.surfaceVariant),
                            ) {
                                if (coverId != null) WebArt(api.coverUrl(coverId), "", 240.dp, if (books) 2f / 3f else 1f, Modifier.fillMaxSize(), placeholderless = true)
                                else Placeholder(list.firstOrNull()?.album?.ifEmpty { null } ?: "Unknown", Modifier.fillMaxSize(), centred = false)
                            }
                            Column(Modifier.padding(top = 20.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(if (pods) "PODCAST" else if (books) "AUDIOBOOK" else "ALBUM", color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, lineHeight = BODY_LINE.em)
                                Text(
                                    route.album.ifEmpty { "Unknown album" }, color = scheme.onBackground, fontSize = MusicLook.displaySize(width).sp, fontWeight = FontWeight.SemiBold,
                                    letterSpacing = (-0.022).em, lineHeight = 1.14.em, modifier = Modifier.padding(bottom = 4.dp).semantics { heading() },
                                )
                                if (pods) Text(route.artist, color = extra.accentText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em)
                                else Text(
                                    route.artist.ifEmpty { "Unknown" }, color = extra.accentText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, lineHeight = BODY_LINE.em,
                                    modifier = Modifier.clickable(remember { MutableInteractionSource() }, null, role = Role.Button) { nav.push(Route.Artist(route.library, route.artist)) },
                                )
                                Text(MusicLook.albumFacts(list, type), color = extra.hint, fontSize = 15.sp, lineHeight = BODY_LINE.em)
                                FlowRow(Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                    WebButton(MusicLook.playWords(type, list), { if (list.isNotEmpty()) playTrack(MusicLook.playFrom(type, list)) }, WebButtonKind.Primary, WebIcons.Play)
                                    discs.filter { it !in gone }.forEach { d ->
                                        WebButton(if (discs.size > 1) "Disc ${discs.indexOf(d) + 1}" else "Insert disc", { nav.push(Route.Page("/cd/$d?play=1")) }, WebButtonKind.Secondary, WebIcons.Disc)
                                    }
                                    if (!books) WebButton("Shuffle", { nav.startListening(list.shuffled(), Start(0), false) })
                                    if (!books && list.isNotEmpty()) WebButton("Station", { nav.startStation(list[0], say) }, WebButtonKind.Ghost, WebIcons.Station)
                                    WebButton("Play next", { listening.playNext(list, keeps); say("Plays next") }, WebButtonKind.Ghost)
                                    WebButton("Add to queue", { listening.addToQueue(list, keeps); say("Added to the queue") }, WebButtonKind.Ghost)
                                    if (!books) WebButton(
                                        if (allLiked) "Liked" else "Like all", { list.forEach { if ((listening.liked[it.id] == true) == allLiked) listening.toggleLike(it.id, say) } },
                                        WebButtonKind.Ghost, if (allLiked) WebIcons.HeartOn else WebIcons.Heart,
                                    )
                                }
                                val about = list.firstOrNull()?.overview.orEmpty()
                                if (about.isNotEmpty() && !pods) {
                                    Text(about, color = scheme.onSurfaceVariant, fontSize = 14.sp, lineHeight = BODY_LINE.em, maxLines = 4, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 12.dp))
                                }
                            }
                        }
                    }
                }
                trackRows(nav, "track", list, episodes = pods, discs = !books, hearts = !books) { playTrack(it) }
                if (versions.isNotEmpty()) item(key = "versions") { AlbumShelf(nav, route.library, "Other versions", versions, null) }
                if (more.isNotEmpty() && !books) item(key = "more") {
                    AlbumShelf(nav, route.library, "More by ${route.artist}", more) { nav.push(Route.Artist(route.library, route.artist)) }
                }
                item(key = "foot") { PageFoot(nav, if (pods) "webMedia" else "metadata") }
            }
        }
        Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = LocalBottomRoom.current - 4.dp))
    }
}

// Other versions, or more by the same artist: a shelf of covers without the artist under them.
@Composable
private fun AlbumShelf(nav: Nav, library: Long, title: String, albums: List<Album>, seeAll: (() -> Unit)?) {
    Shelf(title, seeAll = seeAll) {
        val width = (LocalConfiguration.current.screenWidthDp * 0.16f).coerceIn(130f, 200f).dp
        MhRow { itemsIndexed(albums, key = { i, a -> "$i-${a.title}" }) { _, a -> AlbumTile(nav, library, a, Modifier.width(width), noArtist = true) } }
    }
}

// MARK: an artist or an author

@Composable
private fun ArtistPage(nav: Nav, library: Long, name: String) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    var info by remember(library, name) { mutableStateOf<ArtistInfo?>(null) }
    var failed by remember(library, name) { mutableStateOf(false) }
    var type by remember(library) { mutableStateOf("") }
    var newestFirst by rememberSaveable(library, name) { mutableStateOf(true) }
    var picking by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf("") }
    val say: (String) -> Unit = { toast = it }
    LaunchedEffect(library, name) {
        type = nav.libraryType(library)
        if (type == "music") nav.app.listening.loadLikes(library)
        try {
            info = api.artistInfo(library, name)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) failed = true
        }
    }
    val colour = rememberArtColour(api.artistPhotoUrl(library, name))
    val anchor = remember { GlowAnchor() }
    val state = rememberLazyListState()
    TracksScroll(state)
    val found = info
    if (failed) {
        Box(Modifier.fillMaxSize().padding(top = LocalTopRoom.current)) { MusicEmpty(WebIcons.Audio, "Nobody by that name here", "They may have been moved or renamed.") }
        return
    }
    if (found == null) {
        Box(Modifier.fillMaxSize().padding(top = LocalTopRoom.current)) { MusicSpinner() }
        return
    }
    val books = type == "audiobooks"
    val locale = pageLocale()
    val (full, small) = MusicLook.discography(found.albums, newestFirst, books, locale)
    val top = found.top.ifEmpty { found.tracks.take(5) }
    val width = LocalConfiguration.current.screenWidthDp.toFloat()
    val columns = MusicLook.columns(width - 32f, 104f, 16f)
    Box(Modifier.fillMaxSize()) {
        CompositionLocalProvider(LocalSay provides say) {
            LazyColumn(
                Modifier.fillMaxSize().artGlow(colour, anchor, LocalConfiguration.current.screenHeightDp), state = state,
                contentPadding = PaddingValues(top = LocalTopRoom.current, bottom = LocalBottomRoom.current),
            ) {
                item(key = "head") {
                    GlowGone(anchor)
                    Column(Modifier.fillMaxWidth().glowAnchor(anchor).padding(horizontal = 16.dp)) {
                        TitleBackLink(if (books) "Authors" else "Artists", Modifier.padding(top = 4.dp, bottom = 12.dp)) { nav.openLibraryTab(library, MusicTab.Artists) }
                        ArtistHead(nav, library, name, found, books, width, say)
                    }
                }
                if (top.isNotEmpty() && !books) {
                    item(key = "top-head") { ShelfHead(if (found.top.isNotEmpty()) "Your most played" else "Songs") }
                    trackRows(nav, "top", top, showAlbum = true) { i -> nav.startListening(top, Start(i), false) }
                    item(key = "top-foot") { Spacer(Modifier.height(28.dp)) }
                }
                item(key = "disco-head") {
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(if (books) "Books" else "Discography", color = scheme.onBackground, fontSize = 20.sp, fontWeight = FontWeight.Bold, lineHeight = 1.14.em, modifier = Modifier.weight(1f).semantics { heading() })
                        Select(if (newestFirst) "Newest first" else "By title", "Sort albums") { picking = true }
                    }
                }
                gridRows("full", full, columns) { a -> AlbumTile(nav, library, a, Modifier.fillMaxWidth(), book = books, noArtist = true) }
                if (small.isNotEmpty()) {
                    item(key = "small-head") { ShelfHead("Singles and EPs") }
                    gridRows("small", small, columns, bottom = 28.dp) { a -> AlbumTile(nav, library, a, Modifier.fillMaxWidth(), noArtist = true) }
                }
                item(key = "foot") { PageFoot(nav) }
            }
        }
        if (picking) ChoiceSheet("Sort albums", listOf("year" to "Newest first", "title" to "By title"), if (newestFirst) "year" else "title", { newestFirst = it == "year" }) { picking = false }
        Toast(toast, { toast = "" }, Modifier.align(Alignment.BottomCenter).padding(bottom = LocalBottomRoom.current - 4.dp))
    }
}

// `.mh-artist-head` on a phone: the round picture, then in the middle what they are, their name, the facts, the
// buttons, and the biography with where it's from.
@Composable
private fun ArtistHead(nav: Nav, library: Long, name: String, info: ArtistInfo, books: Boolean, width: Float, say: (String) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    Column(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        ArtistPhoto(nav, library, name, true, Modifier.width(minOf(width * 0.52f, 200f).dp))
        Column(Modifier.padding(top = 20.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(if (books) "AUTHOR" else "ARTIST", color = extra.hint, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.07.em, lineHeight = BODY_LINE.em)
            Text(
                name.ifEmpty { "Unknown" }, color = scheme.onBackground, fontSize = MusicLook.displaySize(width).sp, fontWeight = FontWeight.SemiBold,
                letterSpacing = (-0.022).em, lineHeight = 1.14.em, textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 4.dp).semantics { heading() },
            )
            Text(MusicLook.artistFacts(info, books), color = extra.hint, fontSize = 15.sp, lineHeight = BODY_LINE.em, textAlign = TextAlign.Center)
            FlowRow(
                Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                WebButton("Play", { nav.startListening(info.tracks, Start(0), books) }, WebButtonKind.Primary, WebIcons.Play)
                if (!books) WebButton("Shuffle", { nav.startListening(info.tracks.shuffled(), Start(0), false) })
                if (!books && info.tracks.isNotEmpty()) WebButton("Station", { nav.startStation(info.tracks[0], say) }, WebButtonKind.Ghost, WebIcons.Station)
            }
            val fine = TextLinkStyles(SpanStyle(color = scheme.onSurfaceVariant, textDecoration = TextDecoration.Underline))
            if (info.bio.isNotEmpty()) {
                Text(info.bio, color = scheme.onBackground, fontSize = 15.sp, lineHeight = BODY_LINE.em, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp).widthIn(max = 560.dp))
                if (info.bioUrl.isNotEmpty()) {
                    val credit = buildAnnotatedString {
                        append("From ")
                        withLink(LinkAnnotation.Url(info.bioUrl, fine)) { append("Wikipedia") }
                        append(", available under CC BY-SA 4.0. It's the article with this name, which may not always be the right person.")
                    }
                    Text(credit, color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp).widthIn(max = 560.dp))
                }
            } else if (!info.online && nav.me?.isAdmin == true) {
                val note = buildAnnotatedString {
                    append("Biographies and photos can come from Wikipedia, if you turn on ")
                    withLink(LinkAnnotation.Clickable("settings", fine) { nav.push(Route.Page("/settings/metadata#lyrics", "Settings")) }) { append("online music information") }
                    append(". An ")
                    withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append("artist.jpg") }
                    append(" in their folder is used first.")
                }
                Text(note, color = scheme.onSurfaceVariant, fontSize = 12.sp, lineHeight = BODY_LINE.em, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp).widthIn(max = 560.dp))
            }
        }
    }
}

// A listening library's page at one of its parts, as the website's /library/3?tab=artists, with Home under it.
private fun Nav.openLibraryTab(library: Long, tab: MusicTab) {
    val own = (menu.firstOrNull { it.key == "lib:$library" }?.route as? Route.Library)?.library
    if (own == null) {
        push(Route.Page("/library/$library?tab=${tab.key}"))
        return
    }
    reset(Route.Home)
    push(Route.Library(own, mapOf("tab" to tab.key)))
}

// MARK: the colour behind the top

// Where the colour behind a music page starts: the top of its first part, against the list it's in.
private class GlowAnchor {
    var list by mutableFloatStateOf(0f)
    var top by mutableStateOf<Float?>(null)
}

private fun Modifier.glowAnchor(anchor: GlowAnchor): Modifier = this.onGloballyPositioned { anchor.top = it.positionInRoot().y }

// Once its part has scrolled away, there's no colour left to draw.
@Composable
private fun GlowGone(anchor: GlowAnchor) {
    DisposableEffect(anchor) { onDispose { anchor.top = null } }
}

// The colour from the artwork behind the top of a music page (`.mh-bg`): from 120 above the anchor, the whole width,
// min(720, 90% of the screen) high, a radial gradient 70% by 70% from the top's middle: the colour at 34%, 8% at 60%,
// nothing from 80%.
private fun Modifier.artGlow(colour: Color?, anchor: GlowAnchor, screen: Int): Modifier =
    this.onGloballyPositioned { anchor.list = it.positionInRoot().y }.drawBehind {
        val c = colour ?: return@drawBehind
        val top = anchor.top ?: return@drawBehind
        val y = top - anchor.list - 120.dp.toPx()
        val h = minOf(720.dp.toPx(), screen.dp.toPx() * 0.9f)
        val rx = size.width * 0.7f
        val ry = h * 0.7f
        val centre = Offset(size.width / 2, y)
        clipRect(0f, y, size.width, y + h) {
            scale(1f, ry / rx, centre) {
                drawCircle(Brush.radialGradient(0f to c.copy(alpha = 0.34f), 0.6f to c.copy(alpha = 0.08f), 0.8f to Color.Transparent, center = centre, radius = rx), rx, centre)
            }
        }
    }

// The artwork's colour (audio/art.ts), worked out once for each picture; grey without one.
private val artColours = HashMap<String, Triple<Int, Int, Int>>()
private val NEUTRAL = Triple(120, 120, 135)

@Composable
private fun rememberArtColour(url: String?): Color {
    val context = LocalContext.current
    var rgb by remember(url) { mutableStateOf(url?.let { artColours[it] } ?: NEUTRAL) }
    LaunchedEffect(url) {
        if (url == null || artColours.containsKey(url)) return@LaunchedEffect
        val found = try {
            val request = ImageRequest.Builder(context).data(url).size(64).allowHardware(false).build()
            artColour(SingletonImageLoader.get(context).execute(request).image?.toBitmap())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            NEUTRAL
        }
        artColours[url] = found
        rgb = found
    }
    return Color(rgb.first, rgb.second, rgb.third)
}

// MARK: music videos

// Music videos (music/MusicVideos.tsx): the videos of every music video library this person can see, in artist order
// from the server, each tile naming its artist; a video tied to a song says so under it. 120 at a time, the next as the
// end comes near or with Show more. A video opens on the server's own page for it, as the website's does.
@Composable
private fun MusicVideosTab(nav: Nav, library: Library, head: LazyListScope.() -> Unit, notice: String) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val locale = pageLocale()
    var words by rememberSaveable(library.id) { mutableStateOf("") }
    var search by remember { mutableStateOf(words.trim()) }
    var videos by remember(search) { mutableStateOf<List<com.wittywilla.wittymediaclient.net.MusicVideoCard>?>(null) }
    var more by remember(search) { mutableStateOf(false) }
    var busy by remember(search) { mutableStateOf(false) }
    // A quarter of a second after the last letter.
    LaunchedEffect(words) {
        delay(250)
        search = words.trim()
    }
    suspend fun load(from: Int) {
        if (busy && from > 0) return
        busy = true
        try {
            val page = api.musicVideos(MusicVideos.path(search, from))
            val have = videos
            videos = if (from == 0 || have == null) page.videos else have + page.videos.filter { v -> have.none { it.id == v.id } }
            more = page.more
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (videos == null) videos = emptyList()
        }
        busy = false
    }
    LaunchedEffect(search) { load(0) }
    val list = videos
    val columns = MusicLook.columns(LocalConfiguration.current.screenWidthDp - 32f, 260f, 16f)
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    MusicList(nav, head, notice) {
        item(key = "filters") {
            Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (list != null) Text(MusicVideos.count(list.size, more, locale), color = scheme.onBackground, fontSize = 15.sp, lineHeight = BODY_LINE.em)
                WebInput(words, { words = it }, "Find a video or an artist…", Modifier.fillMaxWidth().semantics { contentDescription = "Find a music video" })
            }
        }
        when {
            list == null -> item(key = "loading") { MusicSpinner() }
            list.isEmpty() -> item(key = "empty") {
                val (title, text) = MusicVideos.empty(search.isNotEmpty())
                MusicEmpty(WebIcons.Channels, title, text)
            }
            else -> {
                val rows = list.chunked(columns)
                itemsIndexed(rows, key = { i, _ -> "videos-$i" }) { i, row ->
                    Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = if (i > 0) 22.dp else 0.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        row.forEach { v -> Box(Modifier.weight(1f)) { MusicVideoTile(nav, v, library.id) } }
                        repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
                // Show more, which also comes by itself as it nears the screen.
                if (more) item(key = "more") {
                    LaunchedEffect(list.size) { load(list.size) }
                    Box(Modifier.fillMaxWidth().padding(top = 8.dp, bottom = 24.dp), contentAlignment = Alignment.Center) {
                        WebButton("Show more", { scope.launch { load(list.size) } }, WebButtonKind.Ghost)
                    }
                }
            }
        }
    }
}

// The newest music videos on a music library's Home, when there are any, with See all.
@Composable
private fun MusicVideosShelf(nav: Nav, library: Library, seeAll: () -> Unit) {
    val api = nav.app.api
    var videos by remember(library.id) { mutableStateOf<List<com.wittywilla.wittymediaclient.net.MusicVideoCard>?>(null) }
    LaunchedEffect(library.id) { videos = runCatching { api.musicVideos(MusicVideos.LATEST_PATH).videos }.getOrDefault(emptyList()) }
    val shown = videos.orEmpty()
    if (shown.isEmpty()) return
    val width = minOf(260f, LocalConfiguration.current.screenWidthDp * 0.7f).dp
    Shelf("Music videos", seeAll = seeAll) {
        // `.ch-shelf-row`: sideways, 10 apart, 3 inside.
        LazyRow(Modifier.fillMaxWidth().padding(horizontal = 13.dp), contentPadding = PaddingValues(3.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
            items(shown, key = { it.id }) { v -> Box(Modifier.width(width)) { MusicVideoTile(nav, v, library.id) } }
        }
    }
}

// A video, and under it the song it's tied to: its album when that's in this library, else its artist.
@Composable
private fun MusicVideoTile(nav: Nav, video: com.wittywilla.wittymediaclient.net.MusicVideoCard, library: Long) {
    val scheme = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        VideoTileBody(nav, video)
        val song = video.song
        val words = MusicVideos.songWords(video)
        if (song != null && words != null) {
            // `.mh-video-song`: 13 in textSecondary on a pill of the panel colour, 2 by 8 inside.
            Pressable(
                {
                    when (val place = MusicVideos.songPlace(song, library)) {
                        is MusicVideoSongPlace.Album -> nav.push(Route.Album(place.library, place.album, place.artist))
                        is MusicVideoSongPlace.Artist -> nav.push(Route.Artist(place.library, place.name))
                    }
                },
                Modifier, shape = RoundedCornerShape(50), fill = scheme.surface, label = words, pressScale = 1f, ring = false,
            ) {
                Row(Modifier.padding(horizontal = 8.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(WebIcons.Audio, null, tint = scheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
                    Text(words, color = scheme.onSurfaceVariant, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

// The website's video tile (creators/parts.tsx `VideoTile`, creators.css `.cr-tile`): the picture 16:9, or 9:16 for a
// vertical video, on the card colour with radius 10, its length at the lower right, a tick once watched and how far in
// along the bottom; 8 under it the creator's picture at 34, and 10 beside that the title in 14 semibold (two lines), the
// creator, and the views and how long ago in 12.
@Composable
private fun VideoTileBody(nav: Nav, video: com.wittywilla.wittymediaclient.net.MusicVideoCard) {
    val api = nav.app.api
    val scheme = MaterialTheme.colorScheme
    val extra = LocalExtraColours.current
    val facts = MusicVideos.facts(video)
    val progress = MusicVideos.progress(video)
    Pressable(
        { nav.push(Route.Page(MusicVideos.watchPath(video.id), video.title)) }, Modifier.fillMaxWidth(), shape = RoundedCornerShape(10.dp), fill = Color.Transparent,
        label = listOf(video.title, video.creator, facts).filter { it.isNotEmpty() }.joinToString(", "), pressScale = 0.985f, ring = false, clip = false,
    ) {
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.fillMaxWidth().aspectRatio(if (video.vertical) 9f / 16f else 16f / 9f).clip(RoundedCornerShape(10.dp)).background(scheme.surfaceVariant)) {
                WebArt(api.videoThumbUrl(video.id, 480, video.updatedAt), "", 260.dp, if (video.vertical) 9f / 16f else 16f / 9f, Modifier.fillMaxSize(), placeholderless = true)
                if (video.durationSec > 0) Text(
                    clock(video.durationSec), color = Color.White, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, style = NUMBERS,
                    modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp).clip(RoundedCornerShape(4.dp)).background(SCRIM).padding(horizontal = 6.dp, vertical = 1.dp),
                )
                if (video.watched) Box(Modifier.align(Alignment.TopStart).padding(6.dp).size(22.dp).clip(CircleShape).background(SCRIM), contentAlignment = Alignment.Center) {
                    Icon(WebIcons.Check, "Watched", tint = Color.White, modifier = Modifier.size(14.dp))
                }
                if (progress > 0) Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(4.dp).background(Color.White.copy(alpha = 0.3f))) {
                    Box(Modifier.fillMaxWidth(progress.toFloat()).fillMaxHeight().background(scheme.primary))
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                CreatorAvatar(nav, video.creatorId, video.creator, video.hasAvatar, 34.dp)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                    Text(video.title, color = scheme.onBackground, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, lineHeight = 1.3.em, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(video.creator, color = extra.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (facts.isNotEmpty()) Text(facts, color = extra.hint, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
        }
    }
}

// A creator's round picture, or their initial in bold white on a colour of their own when there's none, as the
// website's Avatar.
@Composable
private fun CreatorAvatar(nav: Nav, id: Long, name: String, has: Boolean, size: Dp) {
    var broken by remember(id) { mutableStateOf(false) }
    Box(Modifier.size(size).clip(CircleShape).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        if (has && !broken) {
            Box(Modifier.fillMaxSize().background(LocalExtraColours.current.raised))
            val context = LocalContext.current
            val px = with(LocalDensity.current) { size.roundToPx() }
            val request = remember(id, px) { coil3.request.ImageRequest.Builder(context).data(nav.app.api.creatorAvatarUrl(id)).size(px).build() }
            coil3.compose.AsyncImage(request, null, contentScale = androidx.compose.ui.layout.ContentScale.Crop, modifier = Modifier.fillMaxSize(), onError = { broken = true })
        } else {
            Box(Modifier.fillMaxSize().background(Color(androidx.core.graphics.ColorUtils.HSLToColor(floatArrayOf(MusicVideos.avatarHue(name).toFloat(), 0.35f, 0.36f)))), contentAlignment = Alignment.Center) {
                Text(name.trim().take(1).uppercase().ifEmpty { "?" }, color = Color.White, fontSize = (size.value * 0.45f).sp, fontWeight = FontWeight.Bold)
            }
        }
    }
}
