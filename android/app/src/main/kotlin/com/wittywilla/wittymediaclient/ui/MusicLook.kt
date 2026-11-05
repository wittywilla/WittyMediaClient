package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.Album
import com.wittywilla.wittymediaclient.net.Artist
import com.wittywilla.wittymediaclient.net.ArtistInfo
import com.wittywilla.wittymediaclient.net.Item
import java.net.URLEncoder
import java.text.Collator
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.floor

// The website's music, audiobook and podcast pages at phone size (web/src/pages/AudioLibrary.tsx, music/parts.tsx,
// music/ArtistPage.tsx, music/CoverFlow.tsx, music.css): the tabs, sorts, words and order, apart from the screen so
// they can be tested. The iPhone has the same rules in WittyKit's MusicPagesLook.swift.

// A part of a listening library, as the website's tabs name them (?tab=).
enum class MusicTab(val key: String) {
    Home("home"), Albums("albums"), Artists("artists"), Songs("songs"), Videos("videos"), Playlists("playlists");

    companion object {
        fun of(key: String?): MusicTab = entries.firstOrNull { it.key == key } ?: Home
    }
}

object MusicLook {
    // MARK: tabs and sorts

    // A music library has Music videos when this person can see a music videos library (`videos`).
    fun tabs(libraryType: String, videos: Boolean = false): List<Pair<MusicTab, String>> = when (libraryType) {
        "podcasts" -> listOf(MusicTab.Home to "Home", MusicTab.Albums to "Podcasts")
        "audiobooks" -> listOf(MusicTab.Home to "Home", MusicTab.Albums to "Books", MusicTab.Artists to "Authors")
        else -> listOfNotNull(
            MusicTab.Home to "Home", MusicTab.Albums to "Albums", MusicTab.Artists to "Artists", MusicTab.Songs to "Songs",
            if (videos) MusicTab.Videos to "Music videos" else null, MusicTab.Playlists to "Playlists",
        )
    }

    // A sort the header offers, and whether choosing it starts from the other end: newest, most.
    data class Sort(val key: String, val label: String, val desc: Boolean = false)

    fun sorts(tab: MusicTab, libraryType: String, songView: String): List<Sort> {
        val books = libraryType == "audiobooks"
        return when {
            tab == MusicTab.Albums && libraryType != "podcasts" -> listOf(
                Sort("title", "Title"), Sort("artist", if (books) "Author" else "Artist"), Sort("year", "Year", true),
                Sort("added", "Recently added", true), Sort("played", "Most played", true),
            )
            tab == MusicTab.Artists -> listOf(Sort("name", "Name"), Sort("albums", if (books) "Most books" else "Most albums", true))
            tab == MusicTab.Songs && (songView.isEmpty() || songView == "liked") -> listOf(
                Sort("title", "Title"), Sort("artist", "Artist"), Sort("album", "Album"), Sort("year", "Year", true),
                Sort("added", "Date added", true), Sort("runtime", "Length", true),
            )
            else -> emptyList()
        }
    }

    // What a tab starts sorted by.
    fun startSort(tab: MusicTab, libraryType: String): String = when {
        tab == MusicTab.Artists -> "name"
        libraryType == "audiobooks" -> "artist"
        else -> "title"
    }

    // The server answers year, added and played newest first, so the list is read backwards when that isn't asked for.
    fun reversed(sort: String, desc: Boolean): Boolean = desc != (sort == "year" || sort == "added" || sort == "played")

    // The direction button's words for a screen reader.
    fun directionWords(label: String, desc: Boolean): String =
        if (desc) "$label: last to first. Switch to first to last" else "$label: first to last. Switch to last to first"

    // MARK: songs

    // Which songs the Songs tab shows.
    val songViews = listOf("" to "All songs", "liked" to "Liked", "played" to "Most played", "recent" to "Played lately", "added" to "Newest")

    // The Playlists tab's own lists, made from those.
    data class Built(val view: String, val name: String, val about: String)

    val built = listOf(
        Built("liked", "Liked songs", "Everything you've pressed the heart on"),
        Built("played", "Most played", "Your favourites, by how often you play them"),
        Built("recent", "Played lately", "What you've been listening to"),
        Built("added", "Newest", "What came to this library most recently"),
    )

    // What an empty Songs tab says: its title, and the words under it.
    fun emptySongs(view: String, filtered: Boolean): Pair<String, String> {
        val title = when {
            filtered -> "Nothing matches that"
            view == "liked" -> "No liked songs yet"
            view == "played" || view == "recent" -> "Nothing played yet"
            else -> "No songs here"
        }
        return title to if (!filtered && view == "liked") "Press the heart on a song to keep it here." else ""
    }

    // What the Songs tab asks /music/songs for, after the library: a sort only where it means something.
    fun songsQuery(view: String, sort: String, desc: Boolean, genre: String, search: String): String = buildList {
        add("limit=2000")
        if (view.isNotEmpty()) add("view=" + encode(view))
        if (view.isEmpty() || view == "liked") {
            add("sort=" + encode(sort))
            if (desc) add("desc=1")
        }
        if (genre.isNotEmpty()) add("genre=" + encode(genre))
        if (search.isNotEmpty()) add("search=" + encode(search))
    }.joinToString("&")

    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8")

    // MARK: words

    // "1 album", "12 books".
    fun count(n: Int, one: String, many: String): String = "$n ${if (n == 1) one else many}"

    // A number as the browser's toLocaleString writes it: 1,234 in Britain.
    fun number(n: Int, locale: Locale): String = NumberFormat.getIntegerInstance(locale).format(n)

    // What Home's shelf of albums is called.
    fun albumShelf(libraryType: String): String = when (libraryType) { "audiobooks" -> "Books"; "podcasts" -> "Shows"; else -> "Albums" }

    // How many the Albums tab has: podcasts, books or albums.
    fun albumsCount(n: Int, libraryType: String): String = when (libraryType) {
        "podcasts" -> count(n, "podcast", "podcasts")
        "audiobooks" -> count(n, "book", "books")
        else -> count(n, "album", "albums")
    }

    fun artistsCount(n: Int, libraryType: String): String =
        if (libraryType == "audiobooks") count(n, "author", "authors") else count(n, "artist", "artists")

    // An artist's tile counts what's theirs, on a screen wide enough to show it.
    fun artistTileCount(n: Int, libraryType: String): String = when (libraryType) {
        "audiobooks" -> count(n, "book", "books")
        "podcasts" -> count(n, "show", "shows")
        else -> count(n, "album", "albums")
    }

    // "1,234 songs · 3 h 4 min" over the Songs tab's list.
    fun songsCount(songs: List<Item>, locale: Locale): String {
        val total = songs.sumOf { it.runtimeSec }
        return "${number(songs.size, locale)} ${if (songs.size == 1) "song" else "songs"}" + if (total > 0) " · ${runtimeWords(total)}" else ""
    }

    // An album's page plays as music, an audiobook or a podcast, by its library.
    fun mode(libraryType: String): String = if (libraryType == "audiobooks" || libraryType == "podcasts") libraryType else "music"

    // The facts under an album's name: "12 tracks · 48 min · 2013 · Ambient"; a podcast's only counts its episodes.
    fun albumFacts(tracks: List<Item>, libraryType: String): String {
        val mode = mode(libraryType)
        val pods = mode == "podcasts"
        val noun = when {
            pods -> "episodes"
            mode != "music" -> "chapters"
            tracks.size == 1 -> "track"
            else -> "tracks"
        }
        val first = tracks.firstOrNull()
        return listOf(
            "${tracks.size} $noun",
            if (pods) "" else runtimeWords(tracks.sumOf { it.runtimeSec }),
            if (pods) "" else first?.year?.takeIf { it != 0 }?.toString().orEmpty(),
            if (pods) "" else first?.genres?.firstOrNull().orEmpty(),
        ).filter { it.isNotEmpty() }.joinToString(" · ")
    }

    // The facts under an artist's name: "4 albums · 52 songs · 3 h 41 min · Jazz, Soul".
    fun artistFacts(info: ArtistInfo, books: Boolean): String = listOf(
        if (books) count(info.albums.size, "book", "books") else count(info.albums.size, "album", "albums"),
        count(info.tracks.size, "song", "songs"),
        runtimeWords(info.tracks.sumOf { it.runtimeSec }),
        info.genres.take(3).joinToString(", "),
    ).filter { it.isNotEmpty() }.joinToString(" · ")

    // What the album page's Play button says.
    fun playWords(libraryType: String, tracks: List<Item>): String = when {
        libraryType == "podcasts" -> "Play newest"
        started(libraryType, tracks) -> "Continue"
        else -> "Play"
    }

    // A book or podcast with a place kept in any of its tracks.
    fun started(libraryType: String, tracks: List<Item>): Boolean =
        mode(libraryType) != "music" && tracks.any { (it.progress?.positionSec ?: 0.0) > 5 }

    // Where a book starts: the first chapter not finished.
    fun resumeIndex(tracks: List<Item>): Int = maxOf(0, tracks.indexOfFirst { it.progress?.watched != true })

    // Where Play on a book's or an album's page starts: a book at its first unfinished chapter, the rest at the top.
    fun playFrom(libraryType: String, tracks: List<Item>): Int = if (libraryType == "audiobooks") resumeIndex(tracks) else 0

    // How far into a track, 0 to 1.
    fun listened(track: Item): Float {
        val at = track.progress?.positionSec ?: return 0f
        return if (track.runtimeSec > 0) minOf(1.0, at / track.runtimeSec).toFloat() else 0f
    }

    // A podcast episode's line under its title: when it aired and what it's about, 160 letters at most.
    fun episodeLine(track: Item): String = listOf(track.aired, track.overview).filter { it.isNotEmpty() }.joinToString(" · ").take(160)

    // The same album in other versions ("Deluxe", "[2011 Remaster]"): its name without what marks a version.
    fun baseTitle(title: String): String = title.lowercase(Locale.ROOT)
        .replace(Regex("[(\\[{].*?[)\\]}]"), " ")
        .replace(Regex("\\b(deluxe|remaster(ed)?|expanded|special|anniversary|edition|version)\\b"), " ")
        .replace(Regex("[^\\p{L}\\p{N}]+"), " ")
        .trim()

    // MARK: order

    // An artist's albums, newest first or by title: those of seven tracks or more, then the singles and EPs, as tags
    // rarely say. A book is a book whatever its length.
    fun discography(albums: List<Album>, newestFirst: Boolean, books: Boolean, locale: Locale): Pair<List<Album>, List<Album>> {
        val collator = Collator.getInstance(locale)
        val sorted = if (newestFirst) albums.sortedByDescending { it.year ?: 0 } else albums.sortedWith { a, b -> collator.compare(a.title, b.title) }
        return sorted.filter { books || it.tracks >= 7 } to sorted.filter { !books && it.tracks < 7 }
    }

    // The Artists tab: those whose names have the words in them, by most albums when asked, either way round.
    fun shownArtists(artists: List<Artist>, words: String, sort: String, desc: Boolean, locale: Locale): List<Artist> {
        val find = words.lowercase(Locale.ROOT)
        var shown = artists.filter { find.isEmpty() || it.name.lowercase(Locale.ROOT).contains(find) }
        if (sort == "albums") {
            val collator = Collator.getInstance(locale)
            shown = shown.sortedWith { a, b -> if (a.albums != b.albums) a.albums.compareTo(b.albums) else collator.compare(a.name, b.name) }
        }
        return if (desc) shown.asReversed() else shown
    }

    // A list of albums in the order a sort asked for.
    fun shownAlbums(albums: List<Album>, sort: String, desc: Boolean): List<Album> = if (reversed(sort, desc)) albums.asReversed() else albums

    // MARK: sizes

    // Columns in a grid of `repeat(auto-fill, minmax(min, 1fr))`, `gap` apart.
    fun columns(width: Float, min: Float, gap: Float): Int = maxOf(1, floor((width + gap) / (min + gap)).toInt())

    // The cover flow's front cover: min(58vw, 42vh) on a phone, clamp(190, 34vh, 400) wider; a book's always
    // clamp(200, 36vh, 420), as `.cf.tall` outranks the phone's rule.
    fun coverSize(width: Float, height: Float, tall: Boolean): Float = when {
        tall -> (0.36f * height).coerceIn(200f, 420f)
        width <= 600f -> minOf(0.58f * width, 0.42f * height)
        else -> (0.34f * height).coerceIn(190f, 400f)
    }

    // Where a cover sits `d` places from the front: how far across, turned how far, how big and how solid. In between
    // places, as while moving, each changes evenly from one to the next, as the website's transition does.
    data class CoverPlace(val x: Float, val turn: Float, val scale: Float, val alpha: Float)

    fun coverPlace(d: Float, size: Float, phone: Boolean): CoverPlace {
        val a = abs(d)
        val side = d.coerceIn(-1f, 1f)
        val step = if (phone) 0.72f else 0.62f
        val out = if (phone) 0.28f else 0.24f
        val turn = if (phone) 24f else 52f
        val shrink = if (phone) 0.04f else 0.06f
        val alpha = if (a < 1f) 1f - a * (1f - (1.15f - 0.28f)) else 1.15f - a * 0.28f
        return CoverPlace(d * size * step + side * size * out, -side * turn, 1f - a * shrink, alpha)
    }

    // The type that grows with the screen: the album and artist pages' title (--display), and the cover flow's.
    fun displaySize(width: Float): Float = (21.6f + 0.022f * width).coerceIn(30f, 48f)

    fun heroTitleSize(width: Float): Float = (0.032f * width).coerceIn(22.4f, 35.2f)
}
