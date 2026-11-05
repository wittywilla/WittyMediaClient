package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The programme guide's grid, as web/src/pages/tv/GuidePage.tsx in the server's repository builds it: half-hour
// columns, gaps that are cells too so every moment of every channel can be reached, and runs of programmes too short to
// draw that become one cell. Both TVs draw it natively (Apple TV from WittyKit's GuideRules.swift, the same rules);
// GuideRulesTest holds this to the page.

// One cell of a channel's row: a programme, a gap, or a run of short programmes drawn as one.
data class GuideCell(
    val start: Long,
    val end: Long,
    val kind: Kind,
    val title: String,
    // The programme itself. A gap has none.
    val programme: GuideProgramme? = null,
    // What a run of short programmes holds.
    val group: List<GuideProgramme> = emptyList(),
) {
    enum class Kind { Programme, None, Group }

    fun isOn(now: Long) = start <= now && now < end

    // The channel's own "we'll be back", or nothing at all: drawn quieter.
    val isDim: Boolean get() = kind == Kind.None || programme?.kind == "slate"

    // Something that can be recorded: a broadcast on a tuner channel.
    val isBroadcast: Boolean get() = programme?.kind == "broadcast"

    // The one programme of a run that's on at a time, or the cell's own.
    fun programmeAt(time: Long): GuideProgramme? =
        if (kind == Kind.Group) group.firstOrNull { it.start <= time && time < it.end } ?: group.firstOrNull() else programme
}

data class GuideJump(val label: String, val at: Long)

object GuideRules {
    // The grid's columns are half hours.
    const val SLOT = 1800L

    // How much of the schedule is asked for at a time, and the step it's asked for in.
    const val FETCH_HOURS = 8
    const val FETCH_SPAN = 3 * 3600L

    // Rows asked for at a time.
    const val PAGE = 30

    // A cell narrower than this can't show anything: several in a row are drawn as one.
    const val TINY_WIDTH = 14.0

    // How far back and forward the guide goes.
    const val EARLIEST = 2 * 3600L
    const val LATEST = 14 * 86400L

    fun floorSlot(time: Long): Long = time - ((time % SLOT) + SLOT) % SLOT

    // How many half hours fit across: from the viewer's choice of hours, or the screen's width.
    fun slots(hours: Double, width: Double): Int {
        if (hours > 0) return floor(hours * 2 + 0.5).toInt()
        return if (width < 560) 3 else if (width < 1000) 4 else if (width < 1500) 5 else 6
    }

    // The cells of a row for the stretch on screen; gaps are cells too.
    fun cells(channel: GuideChannel?, from: Long, to: Long, pointsPerSecond: Double): List<GuideCell> {
        if (channel == null) return emptyList()
        val gap = if (channel.kind == "library") "Off air" else "No guide data"
        val out = ArrayList<GuideCell>()
        var t = from
        for (p in channel.programmes.sortedBy { it.start }) {
            if (p.end <= from || p.start >= to) continue
            if (p.start > t) out.add(GuideCell(t, p.start, GuideCell.Kind.None, gap))
            out.add(GuideCell(p.start, p.end, GuideCell.Kind.Programme, p.title, p))
            t = max(t, p.end)
        }
        if (t < to) out.add(GuideCell(t, to, GuideCell.Kind.None, gap))
        return groupTiny(out, pointsPerSecond, from, to)
    }

    internal fun groupTiny(cells: List<GuideCell>, pointsPerSecond: Double, from: Long, to: Long): List<GuideCell> {
        if (pointsPerSecond <= 0) return cells
        fun width(c: GuideCell) = (min(c.end, to) - max(c.start, from)) * pointsPerSecond
        val out = ArrayList<GuideCell>()
        var i = 0
        while (i < cells.size) {
            var j = i
            while (j + 1 < cells.size && width(cells[j]) < TINY_WIDTH && width(cells[j + 1]) < TINY_WIDTH) j++
            if (j > i) {
                val run = cells.subList(i, j + 1)
                out.add(GuideCell(run.first().start, run.last().end, GuideCell.Kind.Group, "${run.size} short programmes", group = run.mapNotNull { it.programme }))
                i = j + 1
            } else {
                out.add(cells[i])
                i++
            }
        }
        return out
    }

    // The cell at a time, or the first.
    fun cellAt(time: Long, cells: List<GuideCell>): GuideCell? = cells.firstOrNull { it.start <= time && time < it.end } ?: cells.firstOrNull()

    // Where the guide's window starts after moving by some seconds, held to how far it goes.
    fun shifted(from: Long, seconds: Long, now: Long): Long {
        val low = floorSlot(now) - EARLIEST
        val high = floorSlot(now) + LATEST
        return min(high, max(low, from + seconds))
    }

    private fun calendar(zone: TimeZone, time: Long) = Calendar.getInstance(zone).apply { timeInMillis = time * 1000 }

    private fun startOfDay(zone: TimeZone, time: Long): Calendar = calendar(zone, time).apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    // The first moment of the day a time is in, in seconds.
    fun startOfDay(time: Long, zone: TimeZone = TimeZone.getDefault()): Long = startOfDay(zone, time).timeInMillis / 1000

    // "Tonight 8 PM" and "Tomorrow morning": times people actually jump to.
    fun jumps(now: Long, zone: TimeZone = TimeZone.getDefault()): List<GuideJump> {
        fun at(days: Int, hour: Int): Long = startOfDay(zone, now).apply {
            add(Calendar.DAY_OF_MONTH, days)
            set(Calendar.HOUR_OF_DAY, hour)
        }.timeInMillis / 1000
        val tonight = at(0, 20)
        return listOf(
            if (tonight > now + 1800) GuideJump("Tonight 8 PM", tonight) else GuideJump("Tomorrow 8 PM", at(1, 20)),
            GuideJump("Tomorrow morning", at(1, 8)),
        )
    }

    // Whole days from one day to another's, as a calendar counts them.
    fun daysBetween(from: Long, to: Long, zone: TimeZone = TimeZone.getDefault()): Int {
        val a = startOfDay(zone, from)
        val b = startOfDay(zone, to)
        var n = 0
        if (b.before(a)) {
            while (b.before(a)) { b.add(Calendar.DAY_OF_MONTH, 1); n-- }
        } else {
            while (a.before(b)) { a.add(Calendar.DAY_OF_MONTH, 1); n++ }
        }
        return n
    }

    // "Tonight", "Tomorrow", or the day's name: as someone would say it.
    fun dayWord(time: Long, now: Long, zone: TimeZone = TimeZone.getDefault()): String {
        return when (daysBetween(now, time, zone)) {
            0 -> if (calendar(zone, time).get(Calendar.HOUR_OF_DAY) >= 17) "Tonight" else "Today"
            1 -> "Tomorrow"
            -1 -> "Yesterday"
            else -> dayName(time, zone)
        }
    }

    // "Wed, Nov 4".
    fun dayName(time: Long, zone: TimeZone = TimeZone.getDefault()): String =
        SimpleDateFormat("EEE, MMM d", Locale.getDefault()).apply { timeZone = zone }.format(Date(time * 1000))

    // How the device says times: set from the device's own setting (24-hour or not) when the guide opens.
    @Volatile
    var timeFormat: DateFormat = DateFormat.getTimeInstance(DateFormat.SHORT, Locale.getDefault())

    // "8:30 PM", as the device says times.
    fun clock(time: Long): String = synchronized(this) { timeFormat.format(Date(time * 1000)) }

    fun span(start: Long, end: Long) = "${clock(start)} to ${clock(end)}"

    // "1h 28m": how long, in the fewest words that are still exact enough.
    fun left(seconds: Long): String {
        val m = max(1, floor(seconds / 60.0 + 0.5).toInt())
        if (m < 60) return "$m min"
        val h = m / 60
        return if (m % 60 == 0) "${h}h" else "${h}h ${m % 60}m"
    }

    // The channels a filter shows.
    fun matches(channel: GuideChannel, kind: String, group: String, favourites: Boolean): Boolean =
        (kind.isEmpty() || channel.kind == kind) &&
            (group.isEmpty() || channel.group == group || channel.categories.orEmpty().contains(group)) &&
            (!favourites || channel.favourite)

    // What the server is asked for: a stretch of the schedule, a page of channels, and a filter.
    fun query(from: Long, offset: Int, limit: Int = PAGE, kind: String = "", group: String = "", favourites: Boolean = false): String =
        "/guide?from=$from&hours=$FETCH_HOURS&offset=$offset&limit=$limit&kind=${queryValue(kind)}&group=${queryValue(group)}" +
            if (favourites) "&favourites=1" else ""

    // The programme after this one on the channel that's worth naming: not a slate or a gap.
    fun next(after: GuideProgramme?, cell: GuideCell?, channel: GuideChannel?): GuideProgramme? {
        if (channel == null) return null
        val end = after?.end ?: cell?.end ?: return null
        return channel.programmes.sortedBy { it.start }.firstOrNull { it.start >= end && it.kind != "slate" && it.kind != "none" }
    }

    // A value in an address: everything but letters, digits and -._~ written out, as the page and Apple TV write it.
    fun queryValue(text: String): String {
        val out = StringBuilder()
        for (b in text.toByteArray(Charsets.UTF_8)) {
            val c = b.toInt() and 0xff
            val ch = c.toChar()
            if (ch in 'a'..'z' || ch in 'A'..'Z' || ch in '0'..'9' || ch == '-' || ch == '.' || ch == '_' || ch == '~') out.append(ch)
            else out.append('%').append("%02X".format(c))
        }
        return out.toString()
    }

    // A channel's key as one piece of an address.
    fun pathPart(text: String): String {
        val out = StringBuilder()
        for (b in text.toByteArray(Charsets.UTF_8)) {
            val c = b.toInt() and 0xff
            val ch = c.toChar()
            if (ch in 'a'..'z' || ch in 'A'..'Z' || ch in '0'..'9' || ch == '-' || ch == '_') out.append(ch)
            else out.append('%').append("%02X".format(c))
        }
        return out.toString()
    }

    // The channel so many steps along, going round at the ends, as a remote's channel buttons do. Only those that can
    // be tuned count.
    fun channel(from: String, step: Int, channels: List<GuideChannel>): GuideChannel? {
        val usable = channels.filter { it.canTune }
        if (usable.isEmpty()) return null
        val at = usable.indexOfFirst { it.key == from }
        if (at < 0) return usable[0]
        val count = usable.size
        return usable[((at + step) % count + count) % count]
    }
}

// Each channel once, as it first comes.
fun uniqueChannels(list: List<GuideChannel>): List<GuideChannel> {
    val seen = HashSet<String>()
    return list.filter { seen.add(it.key) }
}

// One recording, past or to come. Each person sees their own; an administrator sees everyone's.
@Serializable
data class Recording(
    val id: Long = 0,
    val channelId: Long? = null,
    val channel: String = "",
    val number: String? = null,
    val title: String = "",
    val sub: String? = null,
    val start: Long = 0,
    val stop: Long = 0,
    // `scheduled`, `recording`, `done`, `failed` or `cancelled`.
    val status: String = "",
    val error: String? = null,
    // Only an administrator is told where its file is.
    val path: String? = null,
    val sizeBytes: Long? = null,
    val ruleId: Long? = null,
) {
    val isFinished: Boolean get() = status == "done" || status == "failed"

    val statusWords: String
        get() = mapOf("scheduled" to "Scheduled", "recording" to "Recording now", "done" to "Done", "failed" to "Failed", "cancelled" to "Cancelled")[status] ?: status

    // "1.2 GB" or "340 MB".
    val sizeWords: String
        get() {
            val b = sizeBytes ?: return ""
            if (b <= 0) return ""
            return if (b > 1_000_000_000) String.format(Locale.ROOT, "%.1f GB", b / 1e9) else "${floor(b / 1e6 + 0.5).toLong()} MB"
        }
}

// Every airing of a title on a channel.
@Serializable
data class RecordingRule(val id: Long = 0, val channelId: Long? = null, val channel: String = "", val title: String = "")

// "Tell me when this starts", kept with the account.
@Serializable
data class TvReminder(val id: Long = 0, val channel: String = "", val title: String = "", val sub: String? = null, val start: Long = 0, val end: Long = 0)

object ReminderRules {
    // A reminder comes up this long before its programme starts.
    const val LEAD = 60L

    // And stays up this long after it has started.
    const val STAYS = 180L

    // The next reminder to come up, among those not already shown.
    fun due(list: List<TvReminder>, shown: Set<Long>, now: Long): TvReminder? =
        list.filter { it.id !in shown && it.end > now && it.start - LEAD <= now && now < it.start + STAYS }.minByOrNull { it.start }

    // When to look again: the next reminder's moment, or null when there's none to wait for.
    fun nextCheck(list: List<TvReminder>, shown: Set<Long>, now: Long): Long? =
        list.filter { it.id !in shown && it.end > now }.map { max(now, it.start - LEAD) }.minOrNull()
}

// Something coming up that matched a search of the schedule.
@Serializable
data class GuideHit(
    val channel: String = "",
    val number: String? = null,
    val name: String? = null,
    val start: Long = 0,
    val end: Long = 0,
    val title: String = "",
    val sub: String? = null,
)

// What the logo service has for a network or studio. It has nothing until the owner agrees to the download.
@Serializable
data class LogoInfo(
    val id: Long? = null,
    val kind: String = "",
    val name: String = "",
    val has: Boolean? = null,
    val version: Long? = null,
    // A picture with its own background, shown on a plate.
    val opaque: Boolean? = null,
)
