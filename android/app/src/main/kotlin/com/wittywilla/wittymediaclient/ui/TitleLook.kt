package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.AttachedVersion
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.ItemFacts
import com.wittywilla.wittymediaclient.net.Season
import com.wittywilla.wittymediaclient.net.ShowDetail
import com.wittywilla.wittymediaclient.net.TitleListings
import com.wittywilla.wittymediaclient.net.TitleTarget
import com.wittywilla.wittymediaclient.net.queryValue
import com.wittywilla.wittymediaclient.player.clock as clockWords
import java.util.Locale

// A film's, an episode's, a disc's and a show's page as the server's website words them at phone size
// (web/src/pages/ItemPage.tsx, ShowPage.tsx, components/edit/TitleExtras.tsx): the words, the facts and which rows
// go behind "⋯". Apart from the screen, so it can be tested without one; the iPhone has the same rules in WittyKit's
// TitlePage.swift.
object TitleLook {
    // MARK: words

    // "1 h 52 min", "48 min", "40 s"; nothing for nothing (fmtRuntime).
    fun runtime(seconds: Double?): String = if (seconds == null) "" else runtimeWords(seconds)

    // "1:02:05" or "4:07": a place in something (fmtTime).
    fun clock(seconds: Double?): String = clockWords(seconds ?: 0.0)

    private val codecs = mapOf(
        "h264" to "H.264", "hevc" to "HEVC", "h265" to "HEVC", "mpeg2video" to "MPEG-2", "mpeg1video" to "MPEG-1", "mpeg4" to "MPEG-4",
        "vc1" to "VC-1", "av1" to "AV1", "vp9" to "VP9", "vp8" to "VP8", "prores" to "ProRes",
    )

    // Video codecs by the names people know.
    fun codec(code: String?): String = if (code.isNullOrEmpty()) "" else codecs[code.lowercase(Locale.ROOT)] ?: code.uppercase(Locale.ROOT)

    private val languages = mapOf(
        "en" to "English", "nl" to "Dutch", "fr" to "French", "de" to "German", "es" to "Spanish", "it" to "Italian", "pt" to "Portuguese", "ja" to "Japanese",
        "zh" to "Chinese", "ko" to "Korean", "ru" to "Russian", "sv" to "Swedish", "da" to "Danish", "no" to "Norwegian", "fi" to "Finnish", "pl" to "Polish",
        "cs" to "Czech", "hu" to "Hungarian", "el" to "Greek", "tr" to "Turkish", "he" to "Hebrew", "ar" to "Arabic", "hi" to "Hindi", "th" to "Thai",
        "eng" to "English", "dut" to "Dutch", "nld" to "Dutch", "fre" to "French", "fra" to "French", "ger" to "German", "deu" to "German", "spa" to "Spanish",
        "ita" to "Italian", "por" to "Portuguese", "jpn" to "Japanese", "chi" to "Chinese", "zho" to "Chinese", "kor" to "Korean", "rus" to "Russian", "und" to "Unknown",
        // The older bibliographic codes discs use.
        "gre" to "Greek", "rum" to "Romanian", "cze" to "Czech", "ice" to "Icelandic", "per" to "Persian", "baq" to "Basque", "slo" to "Slovak", "mac" to "Macedonian",
        "alb" to "Albanian", "arm" to "Armenian", "geo" to "Georgian", "bur" to "Burmese", "may" to "Malay", "wel" to "Welsh", "tib" to "Tibetan", "mul" to "Several languages", "zxx" to "None",
    )

    // A language code by its English name; any other is named by the system, or shown as it is.
    fun language(code: String?): String {
        if (code.isNullOrEmpty()) return "Unknown"
        val lower = code.lowercase(Locale.ROOT)
        languages[lower]?.let { return it }
        if (lower.length in 2..3 && lower.all { it in 'a'..'z' }) {
            val name = Locale.forLanguageTag(lower).getDisplayLanguage(Locale.ENGLISH)
            if (name.isNotEmpty() && name.lowercase(Locale.ROOT) != lower) return name
        }
        return code.uppercase(Locale.ROOT)
    }

    // A list of languages, each named once, in the order they first come.
    fun languages(codes: List<String>?): String = codes.orEmpty().map(::language).distinct().joinToString(", ")

    // The first four genres, and whether there are more ("…").
    fun genres(list: List<String>?): Pair<List<String>, Boolean> = list.orEmpty().let { it.take(4) to (it.size > 4) }

    // "Featurette", "Behind the scenes": a bonus feature's kind, or "Extra".
    fun extraName(type: String?): String {
        val words = (if (type.isNullOrEmpty()) "extra" else type).replace('-', ' ')
        return words.take(1).uppercase(Locale.ROOT) + words.drop(1)
    }

    // "Director's cut · 1080p": another version's button.
    fun versionLabel(version: AttachedVersion): String {
        val label = version.link?.label.orEmpty()
        return label.ifEmpty { version.item.title } + if (version.item.height > 0) " · ${version.item.height}p" else ""
    }

    // "S1 · E2" without the season, for the playlist's number column; a dash when it has none.
    fun playlistNumber(episode: Item): String = episodeLabel(episode).replace(Regex("^S\\d+ · "), "").ifEmpty { "–" }

    // Who may save to a collection: anyone who may post, and kids to their own lists. Not a guest.
    fun canSave(isAdmin: Boolean, kind: String?): Boolean = isAdmin || kind.isNullOrEmpty() || kind == "adult" || kind == "kids"

    // MARK: discs

    fun isDisc(item: Item): Boolean = item.isDisc
    fun isBluray(item: Item): Boolean = item.isBluray

    // "DVD" or "Blu-ray", for labels.
    fun discName(item: Item): String = if (isBluray(item)) "Blu-ray" else "DVD"

    // Whether the disc's main menu comes first, or the film, with the server's default applied.
    fun startsWithMenu(facts: ItemFacts): Boolean = (facts.startMode ?: "menu") != "title"
    fun trayEffect(facts: ItemFacts): Boolean = facts.insertEffect != false

    // An encrypted disc can't be played: nothing here bypasses copy protection.
    fun playable(item: Item, facts: ItemFacts): Boolean = !(isDisc(item) && facts.disc?.scrambled == true)

    // The server's player for Insert, as the disc's own settings start it.
    fun insertPath(item: Item, facts: ItemFacts): String =
        "/play/${item.id}?mode=${if (startsWithMenu(facts)) "menu" else "title"}${if (trayEffect(facts)) "&insert=1" else ""}"

    // "Insert DVD starts with the disc menu · with the tray effect — change it in Disc settings."
    fun discHint(item: Item, facts: ItemFacts, admin: Boolean): String =
        "Insert ${discName(item)} starts with the ${if (startsWithMenu(facts)) "disc menu" else "main feature"}" +
            (if (trayEffect(facts)) " · with the tray effect" else "") + if (admin) " — change it in Disc settings." else "."

    // MARK: the page's parts

    // Under the poster: the library's name, or the show, its season and the episode's number.
    data class Crumb(val words: String, val goes: Goes)

    sealed interface Goes {
        data class Library(val id: Long) : Goes
        data class Show(val id: Long, val season: Int?) : Goes
        data object Nowhere : Goes
    }

    fun crumbs(item: Item, libraryName: String?): List<Crumb> {
        val show = item.showId ?: return if (libraryName == null) emptyList() else listOf(Crumb(libraryName, Goes.Library(item.libraryId)))
        return buildList {
            add(Crumb(item.showTitle.orEmpty(), Goes.Show(show, null)))
            item.season?.let { add(Crumb(if (it == 0) "Specials" else "Season $it", Goes.Show(show, it))) }
            episodeLabel(item).takeIf { it.isNotEmpty() }?.let { add(Crumb(it, Goes.Nowhere)) }
        }
    }

    // One fact in the table under the synopsis. A wide one (the file) takes the whole row.
    data class Fact(val key: String, val value: String, val wide: Boolean = false)

    fun facts(item: Item, facts: ItemFacts, admin: Boolean): List<Fact> = buildList {
        val disc = isDisc(item)
        val main = facts.disc?.titles?.firstOrNull { it.number == facts.disc?.mainTitle }
        val width = facts.width ?: 0
        if (width > 0) {
            var words = "$width×${facts.height ?: 0} ${codec(facts.videoCodec)}"
            if (disc && main != null) {
                val standard = main.standard.orEmpty()
                words += " · ${if (isBluray(item)) standard else standard.uppercase(Locale.ROOT)} ${if (main.wide == true) "16:9" else "4:3"}"
            }
            add(Fact("Video", words))
        }
        if (!facts.audioLangs.isNullOrEmpty()) add(Fact("Audio", languages(facts.audioLangs)))
        if (!facts.subLangs.isNullOrEmpty()) add(Fact("Subtitles", languages(facts.subLangs)))
        val source = if (disc) "${discName(item)} ${if (item.kind.endsWith("-iso")) "image" else "folder"}" else facts.container.orEmpty().uppercase(Locale.ROOT)
        val size = facts.sizeBytes?.takeIf { it > 0 }?.let { "· " + String.format(Locale.ROOT, "%.2f GB", it / 1e9) }.orEmpty()
        add(Fact("Source", "$source $size".trim()))
        if (disc && facts.disc != null) {
            val info = facts.disc
            add(Fact("Disc", "${info.label.orEmpty()} · ${info.titles?.size ?: 0} titles${if (info.hasMenus == true) " · menus" else ""}"))
        }
        if (admin) add(Fact("File", facts.path.orEmpty(), wide = true))
    }

    // How many columns the facts take: as many of at least 170 as fit, 24 apart.
    fun factColumns(width: Double): Int = maxOf(1, ((width + 24) / 194).toInt())

    // What "⋯" holds on a phone: everything but the main action and Save.
    sealed interface MoreRow {
        val words: String

        data class ResumeDisc(override val words: String, val path: String) : MoreRow
        data class DiscFromStart(override val words: String, val path: String) : MoreRow
        data class MainMenu(val path: String) : MoreRow { override val words get() = "Main menu" }
        data object DiscSettings : MoreRow { override val words get() = "Disc settings" }
        data object PlayFromStart : MoreRow { override val words get() = "Play from start" }
        data class NextEpisode(val id: Long) : MoreRow { override val words get() = "Next episode" }
        data object Artwork : MoreRow { override val words get() = "Artwork" }
        data object Edit : MoreRow { override val words get() = "Edit" }
        data object Refresh : MoreRow { override val words get() = "Refresh" }
    }

    fun moreRows(item: Item, facts: ItemFacts, admin: Boolean): List<MoreRow> = buildList {
        val resumes = (item.progress?.resumeSec ?: 0.0) > 0
        if (isDisc(item)) {
            if (resumes) {
                val title = facts.discTitle?.takeIf { it > 0 } ?: facts.disc?.mainTitle?.takeIf { it > 0 } ?: 1
                add(MoreRow.ResumeDisc("Resume from ${clock(item.progress?.positionSec)}", "/play/${item.id}?mode=title&ttn=$title"))
            } else {
                add(MoreRow.DiscFromStart(if (facts.disc?.content == "tv") "Play from the start" else "Play movie", "/play/${item.id}?mode=title&start=0"))
            }
            if (facts.disc?.hasMenus == true) add(MoreRow.MainMenu("/play/${item.id}?mode=menu"))
            if (admin) add(MoreRow.DiscSettings)
        } else {
            if (resumes) add(MoreRow.PlayFromStart)
            item.nextId?.let { add(MoreRow.NextEpisode(it)) }
        }
        if (admin) {
            add(MoreRow.Artwork)
            add(MoreRow.Edit)
            if (isDisc(item) || item.showId == null) add(MoreRow.Refresh)
        }
    }

    // The server's own page for an administrator's tools: the edit window at its Artwork or Match part, or the page
    // itself, whose "⋯" has Refresh and Disc settings.
    fun editPath(target: TitleTarget, id: Long, section: String? = null): String = "/${target.word}/$id" + (section?.let { "?edit=$it" } ?: "")

    // Where the website's links on a title's page go.
    fun genrePath(library: Long, genre: String) = "/library/$library?genre=${queryValue(genre)}"
    fun tagPath(library: Long, tag: String) = "/library/$library?tag=${queryValue(tag)}"
    fun platformPath(library: Long, key: String) = "/library/$library?platform=${queryValue(key)}"
    fun brandPath(kind: String, name: String, library: Long) = "/brand/$kind/${queryValue(name)}?library=$library"

    // Where the details came from, as markdown with its links. A show's page has no Wikidata line, and credits only
    // TMDB's TV side.
    fun credit(provider: String?, id: String?, show: Boolean = false): String? {
        val ref = queryValue(id.orEmpty())
        val ccBySA = "[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)"
        return when (provider.orEmpty()) {
            "wikidata" -> if (show) null else "Facts from [Wikidata](https://www.wikidata.org/wiki/$ref); plot summary from Wikipedia, shared under $ccBySA."
            "tvmaze" -> "TV information from [TVmaze](https://www.tvmaze.com/shows/$ref), shared under $ccBySA."
            "tvdb" -> "Metadata provided by [TheTVDB](https://thetvdb.com). Please consider adding missing information or subscribing."
            "anilist" -> "Anime information from [AniList](https://anilist.co/anime/$ref)."
            "tmdb-tv", "tmdb" -> if (show && provider == "tmdb") null
                else "Details from [TMDB](https://www.themoviedb.org). This product uses the TMDB API but is not endorsed or certified by TMDB."
            else -> null
        }
    }

    // What follows "Nothing plays from these services.": "… Listed for GB, as of 05/11/2026. Data from JustWatch."
    fun listedNote(listings: TitleListings, date: (Long) -> String): String {
        var words = "You're looking at your own copy, on your own server. Listed for ${listings.region}"
        if (listings.asOf > 0) words += ", as of ${date(listings.asOf)}"
        return words + ". " + listings.attribution
    }

    // MARK: a show

    // "10 ep · 3 left", "10 ep · watched", or just "10 ep" before anything has been watched.
    fun seasonLine(season: Season): String {
        val count = season.episodeCount
        val left = season.unwatched
        return when {
            left != null && left > 0 && left < count -> "$count ep · $left left"
            left == 0 -> "$count ep · watched"
            else -> "$count ep"
        }
    }

    // The season a show opens at: the one asked for, else the next episode's, else the first that isn't Specials.
    // -1 is Other videos, the episodes with no season.
    fun openingSeason(detail: ShowDetail, asked: Int?): Int {
        if (asked != null) return asked
        detail.episodes.firstOrNull { it.id == detail.nextUpId }?.season?.let { return it }
        return detail.seasons.firstOrNull { it.number > 0 }?.number ?: detail.seasons.firstOrNull()?.number ?: 0
    }

    fun episodes(detail: ShowDetail, season: Int): List<Item> =
        detail.episodes.distinctBy { it.id }.filter { (it.season ?: -1) == season || (season == -1 && it.season == null) }

    // The episodes with no season, under Other videos.
    fun otherVideos(detail: ShowDetail): List<Item> = detail.episodes.filter { it.season == null }

    // "Play S1 · E1" or "Resume S1 · E2", and what a screen reader says for Resume.
    data class PlayLabel(val words: String, val spoken: String?)

    fun playLabel(next: Item): PlayLabel {
        val label = episodeLabel(next)
        if ((next.progress?.resumeSec ?: 0.0) > 0) return PlayLabel("Resume $label".trim(), "Resume $label from ${clock(next.progress?.positionSec)}")
        return PlayLabel("Play ${label.ifEmpty { next.title }}", null)
    }

    // "3 seasons · 24 episodes", as the website counts them.
    fun seasonsLine(seasons: Int, episodes: Int): String = "$seasons ${if (seasons == 1) "season" else "seasons"} · $episodes episodes"

    // The episode layout: the one chosen here, else the show's own, else the server's, else cards.
    fun episodeView(chosen: String?, show: String?, server: String?): String =
        listOf(chosen, show, server).firstOrNull { !it.isNullOrEmpty() } ?: "cards"

    // "Aired · runtime" under an episode's title.
    fun episodeLine(episode: Item): String = listOf(episode.aired, runtime(episode.runtimeSec)).filter { it.isNotEmpty() }.joinToString(" · ")

    // MARK: sizes

    // The title's size: 28 on a phone, growing with the width up to 44 (clamp(1.75rem, 1.3rem + 1.9vw, 2.75rem)).
    fun titleSize(width: Double): Double = (20.8 + width * 0.019).coerceIn(28.0, 44.0)

    // The backdrop's height: 38% of the window's, between 240 and 560.
    fun heroHeight(window: Double): Double = (window * 0.38).coerceIn(240.0, 560.0)

    // A frame of the video as a poster, which is shown whole on a colour of its own.
    fun isFrame(poster: String?): Boolean = poster.orEmpty().let { it.startsWith("cache:thumb-") || it.startsWith("cache:frame-") }

    // That colour's hue, worked out from the title so it never changes (artHue).
    fun artHue(title: String): Int = titleHue(title).toInt()

    // HSL to red, green and blue from 0 to 1, for the frame's colour.
    fun rgb(hue: Double, saturation: Double, lightness: Double): Triple<Double, Double, Double> {
        val h = ((hue % 360) + 360) % 360
        val a = saturation * minOf(lightness, 1 - lightness)
        fun channel(n: Double): Double {
            val k = (n + h / 30) % 12
            return lightness - a * maxOf(-1.0, minOf(k - 3, 9 - k, 1.0))
        }
        return Triple(channel(0.0), channel(8.0), channel(4.0))
    }
}
