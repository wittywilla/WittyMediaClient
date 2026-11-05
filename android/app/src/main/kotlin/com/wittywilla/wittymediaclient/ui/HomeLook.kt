package com.wittywilla.wittymediaclient.ui

import com.wittywilla.wittymediaclient.net.ForYou
import com.wittywilla.wittymediaclient.net.GuideChannel
import com.wittywilla.wittymediaclient.net.GuideProgramme
import com.wittywilla.wittymediaclient.net.Home
import com.wittywilla.wittymediaclient.net.Hub
import com.wittywilla.wittymediaclient.net.Item
import com.wittywilla.wittymediaclient.net.Show
import com.wittywilla.wittymediaclient.net.UpdateChange
import com.wittywilla.wittymediaclient.net.UpdateStatus
import com.wittywilla.wittymediaclient.net.isRigGame
import java.util.Locale
import kotlin.math.roundToInt

// Home as the server's website builds it (web/src/pages/HomePage.tsx and the parts it uses): its sections, the
// greeting, the hero's facts, what the main button says and does, the words and badges on a card, "On TV now",
// "Can't decide?" and the notice of a newer server. Apart from the screen, so it can be tested without one; the
// iPhone has the same rules in WittyKit's HomeLook.swift.

// One section of Home: the hero, the libraries, a row of cards, On TV now or Can't decide?. `hub` is a row's cards:
// null for the sections that aren't rows, and for recommendations that haven't come.
data class HomeWidget(val id: String, val title: String, val hub: Hub?)

object HomeWidgets {
    const val HERO = "hero"
    const val LIBRARIES = "libraries"
    // Everything in progress, watching, reading and listening, in one row.
    const val JUMP = "jump"
    const val ON_NOW = "onnow"
    const val FOR_YOU = "foryou"
    const val SHUFFLE = "shuffle"

    // Every section in the website's order: the hero, the libraries, Jump back in, On TV now, the recommendations,
    // Next up, the saved views, what's recently added, and Can't decide? last.
    fun list(home: Home, forYou: ForYou?): List<HomeWidget> {
        fun byKey(key: String) = home.hubs.firstOrNull { it.key == key }
        val going = listOf("continue", "continue-reading", "continue-listening").mapNotNull(::byKey)
        val jump = Hub(JUMP, "Jump back in", items = going.flatMap { it.items }, shows = going.flatMap { it.shows })
        val picked = forYou?.let { Hub(FOR_YOU, it.title, items = it.items, shows = it.shows) }
        val list = mutableListOf(
            HomeWidget(HERO, "Featured", null),
            HomeWidget(LIBRARIES, "Your libraries", null),
            HomeWidget(JUMP, "Jump back in", jump),
            HomeWidget(ON_NOW, "On TV now", null),
            HomeWidget(FOR_YOU, "Recommended for you", picked),
        )
        byKey("nextup")?.let { list += HomeWidget(it.key, it.title, it) }
        for (prefix in listOf("view-", "recent-")) home.hubs.filter { it.key.startsWith(prefix) }.forEach { list += HomeWidget(it.key, it.title, it) }
        list += HomeWidget(SHUFFLE, "Can’t decide?", null)
        // A server that sends the same row twice still shows it once.
        return list.distinctBy { it.id }
    }

    // Nothing featured and every row empty: the libraries have nothing in them yet, or are still being looked through.
    fun isEmpty(home: Home): Boolean = home.featured.isEmpty() && home.hubs.all { it.isEmpty }
}

val Hub.isEmpty: Boolean get() = items.isEmpty() && shows.isEmpty()

// "Because you watch Sol Levante", or "Recommended for you" with nothing to say why.
val ForYou.title: String get() = if (because.isNotEmpty()) "Because you watch $because" else "Recommended for you"

// What Home says at the top when nothing is featured: morning from 5 to noon, afternoon until 6, evening otherwise.
object HomeGreeting {
    fun words(hour: Int): String = when (hour) {
        in 5..11 -> "Good morning"
        in 12..17 -> "Good afternoon"
        else -> "Good evening"
    }

    fun line(hour: Int, name: String): String = if (name.isEmpty()) words(hour) else "${words(hour)}, $name"
}

// MARK: the hero

val Item.isBluray: Boolean get() = kind == "bluray-iso" || kind == "bluray-folder"

// An audio CD image, which plays in the server's CD player.
val Item.isCD: Boolean get() = kind == "cd-image"

// "DVD", "Blu-ray" or "CD", for labels.
val Item.discName: String get() = if (isCD) "CD" else if (isBluray) "Blu-ray" else "DVD"

// One fact in the hero's line under the title: words, the age rating in a box of its own, or the score after a star.
sealed interface HeroFact {
    data class Words(val words: String) : HeroFact
    data class Rating(val rating: String) : HeroFact
    data class Score(val score: String) : HeroFact
}

object HeroLook {
    // The year, how long it is, its age rating, its score, the kind of disc, and up to three genres.
    fun facts(item: Item): List<HeroFact> = buildList {
        item.year?.takeIf { it != 0 }?.let { add(HeroFact.Words("$it")) }
        runtimeWords(item.runtimeSec).takeIf { it.isNotEmpty() }?.let { add(HeroFact.Words(it)) }
        if (item.contentRating.isNotEmpty()) add(HeroFact.Rating(item.contentRating))
        item.rating?.takeIf { it != 0.0 }?.let { add(HeroFact.Score(String.format(Locale.ROOT, "%.1f", it))) }
        if (item.isDisc) add(HeroFact.Words(item.discName + if (item.disc?.hasMenus != false) " · interactive menus" else ""))
        item.genres.take(3).filter { it.isNotEmpty() }.forEach { add(HeroFact.Words(it)) }
    }

    // A dot in the gap before each fact, but not beside the rating's box.
    fun dotted(facts: List<HeroFact>, at: Int): Boolean = facts[at] !is HeroFact.Rating && !(at > 0 && facts[at - 1] is HeroFact.Rating)
}

// MARK: the main button

// What the main button does with something (web/src/openItem.tsx), in this app's terms.
sealed interface OpenAction {
    // This app's own video player.
    data object Play : OpenAction
    // A song or a chapter, from its album or book.
    data object Listen : OpenAction
    // This app's own page for it: a game on someone's own PC.
    data object Page : OpenAction
    // The server's own page: a book's reader, a disc's or a CD's player, a game.
    data class Server(val path: String) : OpenAction
}

object OpenLook {
    // Worded for what it is: Read, Listen, Insert disc, and Play or Resume for the rest.
    fun label(item: Item): String {
        val started = (item.progress?.resumeSec ?: 0.0) > 0
        return when (item.kind) {
            "book" -> if (started) "Continue reading" else "Read"
            "audio" -> if (started) "Continue listening" else "Listen"
            "game" -> "Play"
            "cd-image" -> if (started) "Continue the disc" else "Insert disc"
            else -> if (started) "Resume" else "Play"
        }
    }

    fun action(item: Item): OpenAction = when (item.kind) {
        "book" -> OpenAction.Server(if (item.reader.isEmpty()) "/item/${item.id}" else "/read/${item.id}")
        "game" -> if (item.isRigGame) OpenAction.Page else OpenAction.Server("/game/${item.id}")
        "cd-image" -> OpenAction.Server("/cd/${item.id}?play=1")
        "audio" -> OpenAction.Listen
        "video" -> OpenAction.Play
        else -> OpenAction.Server("/play/${item.id}")
    }

    // A disc's menus, from the hero.
    fun discMenu(item: Item): String = "/play/${item.id}?mode=menu"
}

// MARK: cards

enum class CardShape { Poster, Wide, Square }

// The plates on a card's picture: the kind of disc at the top left, and watched or how many are left at the right.
sealed interface CardBadge {
    data class Disc(val name: String) : CardBadge
    data object Seen : CardBadge
    data class Unwatched(val count: Int) : CardBadge
}

// What a screen reader hears for a plate, as the website labels it.
val CardBadge.spoken: String get() = when (this) {
    is CardBadge.Disc -> name
    CardBadge.Seen -> "Watched"
    is CardBadge.Unwatched -> "$count unwatched"
}

// A card's words, shape and plates, as the website's ItemCard and ShowCard (web/src/components/common.tsx). `progress`
// is how far through, from 0 to 1, for the bar along the bottom: null for none.
data class CardLook(val title: String, val subtitle: String, val shape: CardShape, val badges: List<CardBadge>, val progress: Float?) {
    companion object {
        // Episodes are wide stills with their show's name, unless told otherwise; songs and CDs are square.
        fun item(item: Item, wide: Boolean = item.showId != null): CardLook {
            val audio = item.kind == "audio" || item.isCD
            // Books count pages or chapters in runtimeSec, so their length isn't a time.
            val length = if (item.kind == "book" || audio) "" else runtimeWords(item.runtimeSec)
            val year = item.year?.takeIf { it != 0 }?.toString().orEmpty()
            val p = item.progress
            val progress = if (p != null && p.durationSec > 0 && !p.watched) (p.positionSec / p.durationSec).coerceAtMost(1.0).toFloat().takeIf { it > 0f } else null
            val badges = buildList {
                if (item.isDisc || item.isCD) add(CardBadge.Disc(item.discName))
                if (p?.watched == true) add(CardBadge.Seen)
            }
            val subtitle = when {
                item.showId != null -> listOf(episodeLabel(item), if (wide) item.title else runtimeWords(item.runtimeSec)).filter { it.isNotEmpty() }.joinToString(" · ")
                audio -> item.albumArtist.ifEmpty { item.artist }
                item.kind == "book" -> item.artist.ifEmpty { year }
                else -> listOf(year, length).filter { it.isNotEmpty() }.joinToString(" · ")
            }
            val title = if (!item.showTitle.isNullOrEmpty() && wide) item.showTitle else item.title
            return CardLook(title, subtitle, if (audio) CardShape.Square else if (wide) CardShape.Wide else CardShape.Poster, badges, progress)
        }

        // "2019 · 3 seasons", with how many episodes are left, or a tick once they're all watched.
        fun show(show: Show): CardLook {
            val seasons = "${show.seasonCount} ${if (show.seasonCount == 1) "season" else "seasons"}"
            val subtitle = listOfNotNull(show.year?.takeIf { it != 0 }?.toString(), seasons).joinToString(" · ")
            val badges = buildList {
                if (show.unwatched > 0 && show.unwatched < show.episodeCount) add(CardBadge.Unwatched(show.unwatched))
                if (show.unwatched == 0) add(CardBadge.Seen)
            }
            return CardLook(show.title, subtitle, CardShape.Poster, badges, null)
        }
    }
}

// A frame from the video as a poster, the scan's or one chosen in the artwork picker: shown whole on a card.
val Item.hasGeneratedArt: Boolean get() = poster.startsWith("cache:thumb-") || poster.startsWith("cache:frame-")

// A colour of its own for a card without a real poster, worked out from its title, so it never changes. As the
// website counts it: one step for each character, from the first half of one that takes two.
fun titleHue(title: String): Float {
    var h = 0
    var i = 0
    while (i < title.length) {
        h = (h * 31 + title[i].code) % 360
        i += Character.charCount(Character.codePointAt(title, i))
    }
    return h.toFloat()
}

// MARK: On TV now

object OnNowLook {
    // How many channels Home asks for.
    const val LIMIT = 16

    // Favourites first, the rest in the server's order.
    fun ordered(channels: List<GuideChannel>): List<GuideChannel> = channels.distinctBy { it.key }.sortedBy { if (it.favourite) 0 else 1 }

    fun programme(channel: GuideChannel, now: Double): GuideProgramme? = channel.programmes.firstOrNull { it.start <= now && it.end > now }

    // What's on, or why there's nothing.
    fun title(channel: GuideChannel, now: Double): String =
        programme(channel, now)?.title?.ifEmpty { null } ?: if (channel.kind == "library") "Off air" else "No guide data"

    // The channel's name, and how long is left of what's on.
    fun detail(channel: GuideChannel, now: Double): String {
        val on = programme(channel, now) ?: return channel.name
        return "${channel.name} · ${left(on.end - now)} left"
    }

    // How far into what's on, from 0 to 1.
    fun fraction(channel: GuideChannel, now: Double): Float {
        val on = programme(channel, now) ?: return 0f
        if (on.end <= on.start) return 0f
        return ((now - on.start) / (on.end - on.start)).toFloat().coerceIn(0f, 1f)
    }

    // "12 min", "1h 5m", "2h" (the guide's fmtLeft). Never under a minute.
    fun left(seconds: Double): String {
        val minutes = maxOf(1, (seconds / 60).roundToInt())
        if (minutes < 60) return "$minutes min"
        val hours = minutes / 60
        return if (minutes % 60 != 0) "${hours}h ${minutes % 60}m" else "${hours}h"
    }

    fun spoken(channel: GuideChannel, now: Double): String =
        "Channel ${channel.number}, ${channel.name}: ${programme(channel, now)?.title?.ifEmpty { null } ?: "nothing listed"}"
}

// MARK: Can't decide?

object ShuffleLook {
    // The year, how long it is, and two genres.
    fun facts(item: Item): String =
        listOf(item.year?.takeIf { it != 0 }?.toString().orEmpty(), runtimeWords(item.runtimeSec), item.genres.take(2).joinToString(", "))
            .filter { it.isNotEmpty() }.joinToString(" · ")
}

// MARK: a newer server

object UpdateNews {
    // For administrators only, until they choose Later for that version.
    fun shows(update: String, admin: Boolean, later: String): Boolean = update.isNotEmpty() && admin && later != update

    fun title(version: String): String = "WittyMediaServer $version is available"

    private val point = Regex("[-*+] (.*)")
    private val bold = Regex("^\\*\\*(.+?)\\*\\*")
    private val marks = Regex("\\*\\*|__|`|\\[([^\\]]*)\\]\\([^)]*\\)")
    private val lastWord = Regex("\\s+\\S*$")

    // The newest version's first change in a few words, and how many more changes there are since this one. The
    // changelog leads each change with its point in bold.
    fun headline(changes: List<UpdateChange>): Pair<String, Int> {
        var first = ""
        var count = 0
        for (change in changes) {
            for (line in change.notes.split("\n")) {
                val said = point.matchEntire(line)?.groupValues?.get(1) ?: continue
                count++
                if (first.isNotEmpty()) continue
                var words = bold.find(said)?.groupValues?.get(1) ?: said
                words = marks.replace(words) { it.groupValues[1] }.trim()
                if (words.endsWith(".") || words.endsWith(":")) words = words.dropLast(1)
                if (words.length > 90) words = lastWord.replace(words.take(88), "") + "…"
                first = words
            }
        }
        return first to maxOf(0, count - if (first.isEmpty()) 0 else 1)
    }

    // What the notice says under its title.
    fun sentence(status: UpdateStatus): String {
        val (first, more) = headline(status.latest?.changes.orEmpty())
        if (first.isEmpty()) return "A newer version of the server is ready to install."
        return first + (if (more > 0) ", and $more more ${if (more == 1) "change" else "changes"}" else "") + "."
    }

    // The main button: Docker is updated by its owner.
    fun action(status: UpdateStatus?): String = if (status?.method == "docker") "How to update" else "Update"
}
