// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.net

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Calendar
import java.util.TimeZone

// Profiles on a shared screen and parental controls (the server's docs/PROFILES.md): what the server says about a
// profile, and the rules an app needs around it. Every limit is applied by the server; this is only for showing
// what is so, hiding what is off, and sending a parent's changes. No screen in here, so it can be tested without one.

const val FEATURE_SWITCHING = "profile-switching"
const val FEATURE_AVATARS = "profile-avatars"
const val FEATURE_PARENTAL = "parental-controls"
const val FEATURE_SCREEN_TIME = "screen-time"

// One of the people on this server, as Who's watching shows them. hasPassword is false only where a tap is enough.
@Serializable
data class HouseholdProfile(
    val id: Long = 0,
    val name: String = "",
    val displayName: String = "",
    val kind: String = "adult",
    val hasPassword: Boolean = true,
    val avatar: String = "",
    val current: Boolean = false,
)

@Serializable
data class Household(val profiles: List<HouseholdProfile> = emptyList())

// Time left now. -1 for allowance and remaining means no allowance. until and nextAt are Unix seconds, 0 for none.
@Serializable
data class ScreenTime(
    val allowed: Boolean = true,
    val reason: String = "",
    val allowanceSec: Int = -1,
    val usedSec: Int = 0,
    val extraSec: Int = 0,
    val remainingSec: Int = -1,
    val message: String = "",
    val until: Long = 0,
    val nextAt: Long = 0,
)

@Serializable
data class TimeRules(
    val schoolDayMinutes: Int = 0,
    val weekendMinutes: Int = 0,
    val from: String = "",
    val schoolNightUntil: String = "",
    val weekendUntil: String = "",
) {
    val empty: Boolean get() = schoolDayMinutes <= 0 && weekendMinutes <= 0 && from.isEmpty() && schoolNightUntil.isEmpty() && weekendUntil.isEmpty()
}

@Serializable
data class KindLimit(val maxAge: Int = -1, val allowUnrated: Boolean = true)

// GET /me/limits: what the signed-in profile may do. A feature the server doesn't name is on.
@Serializable
data class MyLimits(
    val limited: Boolean = false,
    val kind: String = "adult",
    val features: Map<String, Boolean> = emptyMap(),
    val maxAge: Int = -1,
    val allowUnrated: Boolean = true,
    val time: TimeRules? = null,
    val screenTime: ScreenTime = ScreenTime(),
    val parentPin: Boolean = false,
) {
    fun can(feature: String): Boolean = features[feature] ?: true
    val timed: Boolean get() = time != null && !time.empty
}

// The switches under "What they can do", in the web's order. `adultOnly`: never for a Kids or Guest profile.
data class FeatureSwitch(val id: String, val adultOnly: Boolean = false)

val FEATURE_SWITCHES = listOf(
    FeatureSwitch("games"), FeatureSwitch("recordings"), FeatureSwitch("downloads"), FeatureSwitch("sharing", adultOnly = true),
    FeatureSwitch("comments"), FeatureSwitch("remote"), FeatureSwitch("editProfile"),
)

// An account's limits, as PUT /users/{id}/access takes them. Lists the server sends as null are empty.
@Serializable
data class Access(
    val maxAge: Int = -1,
    val allowUnrated: Boolean = true,
    val libraries: List<Long> = emptyList(),
    val blockGenres: List<String> = emptyList(),
    val allowItems: List<Long> = emptyList(),
    val blockItems: List<Long> = emptyList(),
    val allowShows: List<Long> = emptyList(),
    val blockShows: List<Long> = emptyList(),
    val liveTv: Boolean = true,
    val libraryChannels: Boolean = true,
    val tunerChannels: Boolean = true,
    val kinds: Map<String, KindLimit> = emptyMap(),
    val onlyGenres: List<String> = emptyList(),
    val blockTags: List<String> = emptyList(),
    val allowCollections: List<Long> = emptyList(),
    val blockCollections: List<Long> = emptyList(),
    val off: List<String> = emptyList(),
    val time: TimeRules = TimeRules(),
) {
    fun can(feature: String) = feature !in off
    fun with(feature: String, on: Boolean) = copy(off = if (on) off - feature else (off - feature) + feature)
}

// Someone this account may manage, from GET /users.
@Serializable
data class ManagedUser(
    val id: Long = 0,
    val name: String = "",
    val displayName: String = "",
    val isAdmin: Boolean = false,
    val kind: String = "adult",
    val hasPassword: Boolean = true,
    val twoFactor: Boolean = false,
    val avatar: String = "",
    val access: Access? = null,
)

@Serializable
data class Rating(val label: String = "", val age: Int = 0)

@Serializable
data class RatingSystem(val id: String = "", val name: String = "", val country: String = "", val kinds: List<String> = emptyList(), val ratings: List<Rating> = emptyList())

// GET /parental/ratings: what a settings page offers. Fixed for a server.
@Serializable
data class ParentalLists(
    val kinds: List<String> = emptyList(),
    val systems: List<RatingSystem> = emptyList(),
    val features: List<String> = emptyList(),
    val avatars: List<String> = emptyList(),
    val avatarColours: List<String> = emptyList(),
    val maxExtraMinutes: Int = 240,
)

@Serializable
data class ActivityDay(val day: Int = 0, val screenSec: Int = 0, val extraSec: Int = 0)

@Serializable
data class ActivityWatch(val day: Int = 0, val itemId: Long = 0, val title: String = "", val showTitle: String = "", val kind: String = "", val seconds: Double = 0.0, val lastAt: Long = 0)

@Serializable
data class ActivityEvent(val at: Long = 0, val kind: String = "", val title: String = "", val detail: String = "")

@Serializable
data class ProfileActivity(
    val days: List<ActivityDay> = emptyList(),
    val watched: List<ActivityWatch> = emptyList(),
    val events: List<ActivityEvent> = emptyList(),
    val screenTime: ScreenTime = ScreenTime(),
)

// A refusal the server explains: {"code": "screen-time", "screenTime": {...}} or {"code": "feature-off", "feature": "games"}.
data class Refusal(val code: String = "", val feature: String = "", val screenTime: ScreenTime? = null, val message: String = "") {
    val isScreenTime: Boolean get() = code == "screen-time"
    val isFeatureOff: Boolean get() = code == "feature-off"

    companion object {
        fun read(body: String): Refusal = runCatching {
            val o = json.parseToJsonElement(body).jsonObject
            Refusal(
                code = o["code"]?.jsonPrimitive?.content.orEmpty(),
                feature = o["feature"]?.jsonPrimitive?.content.orEmpty(),
                screenTime = o["screenTime"]?.let { runCatching { json.decodeFromJsonElement(ScreenTime.serializer(), it) }.getOrNull() },
                message = o["error"]?.jsonPrimitive?.content.orEmpty(),
            )
        }.getOrDefault(Refusal())

        fun of(e: Throwable): Refusal? = (e as? ApiError)?.takeIf { it.status == 403 && it.code.isNotEmpty() }?.let { read(it.body) }
    }
}

object ScreenTimeRules {
    // "A few minutes before, a line at the foot of the page says how long is left": the web's ten minutes.
    const val NOTICE_SEC = 600
    const val ASK_EVERY_MS = 60_000L
    private const val AT_UNTIL_SLACK_MS = 1500L
    private const val HOUR_MS = 3_600_000L

    // The words' number: whole minutes left, at least one, or null when no notice is due.
    fun minutesLeftNotice(st: ScreenTime?): Int? {
        if (st == null || !st.allowed || st.remainingSec < 0 || st.remainingSec > NOTICE_SEC) return null
        return maxOf(1, Math.round(st.remainingSec / 60f))
    }

    fun timeUp(st: ScreenTime?): Boolean = st != null && !st.allowed

    // The line is shown again, for a few seconds, each time the minutes left pass one of these.
    val NOTICE_AT = listOf(10, 5, 3, 2, 1)

    // Which of those the time left has reached: the smallest that is still at or above it. More than ten minutes
    // left, no allowance, or time up: none (a large number), so the next time under ten minutes counts as new.
    fun noticeStep(st: ScreenTime?): Int {
        val minutes = minutesLeftNotice(st) ?: return Int.MAX_VALUE
        return NOTICE_AT.filter { it >= minutes }.minOrNull() ?: Int.MAX_VALUE
    }

    // When to ask again: in a minute, or just after `until` when that comes sooner (the moment time runs out).
    fun nextAskMs(st: ScreenTime?, nowMs: Long): Long {
        val untilMs = if (st != null && st.allowed && st.until > 0) st.until * 1000 - nowMs + AT_UNTIL_SLACK_MS else 0
        return if (untilMs in 1 until minOf(ASK_EVERY_MS, HOUR_MS)) untilMs else ASK_EVERY_MS
    }

    // X-WMS-Screen-Time-Left on an answer that played something: the same verdict with the newer number. Zero is
    // only a hint that time is up; the refusal itself, or asking, says why.
    fun withHeader(st: ScreenTime?, leftSec: Int, nowSec: Long): ScreenTime? {
        if (st == null || leftSec < 0 || !st.allowed) return st
        if (leftSec == 0) return st
        return st.copy(remainingSec = leftSec, until = if (st.until > 0) nowSec + leftSec else st.until)
    }

    // More time was given, or a new day began.
    fun allowedAgain(before: ScreenTime?, now: ScreenTime): Boolean = before != null && !before.allowed && now.allowed

    // Whether `nextAt` is today, for "You can watch again at 7:00" against "tomorrow at 7:00".
    fun nextIsToday(nextAtSec: Long, nowMs: Long, zone: TimeZone): Boolean {
        val a = Calendar.getInstance(zone).apply { timeInMillis = nextAtSec * 1000 }
        val b = Calendar.getInstance(zone).apply { timeInMillis = nowMs }
        return a.get(Calendar.YEAR) == b.get(Calendar.YEAR) && a.get(Calendar.DAY_OF_YEAR) == b.get(Calendar.DAY_OF_YEAR)
    }

    // What a parent may give in one go, of the three the notice offers.
    val EXTRA_CHOICES = listOf(15, 30, 60)

    // The parents' PIN is 4 to 12 digits.
    fun typedPin(text: String): String = text.filter { it in '0'..'9' }.take(12)
    fun pinReady(pin: String): Boolean = pin.length in 4..12 && pin.all { it in '0'..'9' }
}

object TimeOfDay {
    private const val DEFAULT_FROM = 6 * 60
    const val MAX_DAY_MINUTES = 24 * 60

    // "20:30" as minutes into the day; null for anything else, exactly as the server reads it.
    fun minutes(text: String): Int? {
        if (text.length != 5 || text[2] != ':') return null
        if (listOf(0, 1, 3, 4).any { text[it] !in '0'..'9' }) return null
        val h = text.substring(0, 2).toInt()
        val m = text.substring(3, 5).toInt()
        return if (h > 23 || m > 59) null else h * 60 + m
    }

    fun text(minutes: Int): String = "%02d:%02d".format(minutes / 60, minutes % 60)

    // What someone types, made into the server's form where it can be: "7:5" is nothing, "7:05" and "0705" are 07:05.
    fun tidy(typed: String): String {
        val t = typed.trim()
        if (t.isEmpty()) return ""
        val digits = t.filter { it in '0'..'9' }
        val formed = when {
            ':' in t -> t.split(':').takeIf { it.size == 2 && it[0].length in 1..2 && it[1].length == 2 }?.let { it[0].padStart(2, '0') + ":" + it[1] }
            digits.length == 4 && digits.length == t.length -> digits.substring(0, 2) + ":" + digits.substring(2)
            digits.length == 3 && digits.length == t.length -> "0" + digits.substring(0, 1) + ":" + digits.substring(1)
            else -> null
        }
        return formed ?: t
    }

    // What is wrong with these rules, as a key for the words, or null. The server's own check, so a parent is told
    // before saving and not by a refusal.
    fun problem(t: TimeRules): String? {
        if (listOf(t.schoolDayMinutes, t.weekendMinutes).any { it < 0 || it > MAX_DAY_MINUTES }) return "timeErrMinutes"
        var from = -1
        if (t.from.isNotEmpty()) from = minutes(t.from) ?: return "timeErrNotTime"
        for (until in listOf(t.schoolNightUntil, t.weekendUntil)) {
            if (until.isEmpty()) continue
            val m = minutes(until) ?: return "timeErrNotTime"
            if (m <= (if (from < 0) DEFAULT_FROM else from)) return "timeErrBedtime"
        }
        return null
    }
}

object Managing {
    // The ages the first choice offers, as the web's: -1 is Everything.
    val AGE_LEVELS = listOf(0, 7, 10, 13, 16, -1)

    // The allowances a day, in minutes; 0 is no limit.
    val ALLOWANCES = listOf(0, 30, 45, 60, 90, 120, 180, 240, 360)

    fun allowances(current: Int): List<Int> = if (current in ALLOWANCES) ALLOWANCES else (ALLOWANCES + current).sorted()

    // The ages worth offering for a kind: each one where some system's next rating begins.
    fun agesFor(systems: List<RatingSystem>, kind: String, current: Int? = null): List<Int> {
        val ages = systems.filter { kind in it.kinds }.flatMap { s -> s.ratings.map { it.age } }.toMutableSet()
        if (current != null && current >= 0) ages += current
        return ages.sorted()
    }

    // The ratings of each system that an age lets through, the highest of each: "PG-13, 12A, FSK 12".
    fun allowedAt(systems: List<RatingSystem>, kind: String, age: Int): String =
        systems.filter { kind in it.kinds }.mapNotNull { s -> s.ratings.lastOrNull { it.age <= age }?.label }.distinct().joinToString(", ")

    // The same for the age over everything, whatever the kind: one rating a system, films' first.
    fun allowedOverall(systems: List<RatingSystem>, age: Int): String =
        systems.filter { "film" in it.kinds || "tv" in it.kinds }.mapNotNull { s -> s.ratings.lastOrNull { it.age <= age }?.label }.distinct().joinToString(", ")

    // GET /users lists only who this account manages (the server decides: an administrator everyone, an adult the
    // Kids profiles unless the administrator keeps that, nobody for an adult with limits or a Kids profile). Within
    // that list: nobody sets their own limits, and an administrator has none.
    fun mayLimit(meId: Long, target: ManagedUser): Boolean = target.id != meId && !target.isAdmin
    fun mayRename(meId: Long, target: ManagedUser): Boolean = target.id != meId
    // Whether Profiles has anything to manage at all: adults only, and the server's list says the rest.
    fun mayManageAnyone(isAdmin: Boolean, kind: String): Boolean = isAdmin || kind == "adult"

    // Their own name and picture: adults unless their limits turn it off, and a Kids or Guest profile given it.
    fun ownLook(isAdmin: Boolean, limits: MyLimits?): Boolean = isAdmin || limits == null || limits.can("editProfile")
    fun ownUsername(isAdmin: Boolean, kind: String, limits: MyLimits?): Boolean = isAdmin || (kind == "adult" && (limits == null || limits.can("editProfile")))

    // A day as the report writes it, 20261111, taken apart.
    fun dayParts(day: Int): Triple<Int, Int, Int> = Triple(day / 10000, day / 100 % 100, day % 100)

    // The days the report has anything for, newest first.
    fun reportDays(a: ProfileActivity): List<Int> = (a.days.map { it.day } + a.watched.map { it.day }).distinct().sortedDescending()
}

private val whole = Json { encodeDefaults = true; explicitNulls = false }

// What changed between the limits as they were read and as they are now, by field: only that is sent, because
// "what isn't sent stays as it was", so a limit a newer server has and this app doesn't know is never cleared.
// kinds and time are each sent whole when anything in them changed, as the server replaces them whole.
fun accessDiff(before: Access, after: Access): JsonObject {
    val a = whole.encodeToJsonElement(Access.serializer(), before).jsonObject
    val b = whole.encodeToJsonElement(Access.serializer(), after).jsonObject
    return buildJsonObject { for ((key, value) in b) if (a[key] != value) put(key, value) }
}

fun accessBody(change: JsonObject, clearPassword: Boolean = false): String = buildJsonObject {
    if (change.isNotEmpty()) put("access", change)
    if (clearPassword) put("clearPassword", JsonPrimitive(true))
}.toString()

@Serializable
private data class SwitchAsk(val name: String, val password: String, val code: String, val device: String)

@Serializable
private data class ExtraAsk(val minutes: Int, val pin: String? = null, val name: String? = null, val password: String? = null)

@Serializable
private data class PinChange(val pin: String, val current: String, val code: String)

@Serializable
data class PinStatus(val set: Boolean = false)

@Serializable
private data class LookChange(val displayName: String? = null, val username: String? = null, val avatar: String? = null)

suspend fun Api.household(): Household = json.decodeFromString(call("GET", "/profiles/household"))

// Signing in as another profile and out of this one, in one step. Refusals: 401 with twoFactor asks for the code
// (or says it was wrong), 403 is a wrong password with this device still signed in as before, 429 says how long to wait.
suspend fun Api.switchProfile(name: String, password: String, code: String, device: String): LoginResult =
    json.decodeFromString(call("POST", "/profiles/switch", json.encodeToString(SwitchAsk(name, password, code, device))))

suspend fun Api.myLimits(): MyLimits = json.decodeFromString(call("GET", "/me/limits"))
suspend fun Api.myScreenTime(): ScreenTime = json.decodeFromString(call("GET", "/me/screen-time"))

suspend fun Api.askParentByPin(minutes: Int, pin: String): ScreenTime =
    json.decodeFromString(call("POST", "/me/screen-time/extra", json.encodeToString(ExtraAsk(minutes, pin = pin))))

suspend fun Api.askParentByPassword(minutes: Int, name: String, password: String): ScreenTime =
    json.decodeFromString(call("POST", "/me/screen-time/extra", json.encodeToString(ExtraAsk(minutes, name = name, password = password))))

suspend fun Api.parentalLists(): ParentalLists = json.decodeFromString(call("GET", "/parental/ratings"))
suspend fun Api.managedUsers(): List<ManagedUser> = json.decodeFromString<List<ManagedUser>?>(call("GET", "/users")).orEmpty()

suspend fun Api.saveAccess(id: Long, change: JsonObject, clearPassword: Boolean = false): ManagedUser =
    json.decodeFromString(call("PUT", "/users/$id/access", accessBody(change, clearPassword)))

suspend fun Api.profileActivity(id: Long, days: Int = 14): ProfileActivity = json.decodeFromString(call("GET", "/users/$id/activity?days=$days"))
suspend fun Api.clearProfileActivity(id: Long) { call("DELETE", "/users/$id/activity") }

suspend fun Api.giveTime(id: Long, minutes: Int): ScreenTime =
    json.decodeFromString(call("POST", "/users/$id/screen-time/extra", "{\"minutes\":$minutes}"))

suspend fun Api.parentPinSet(): Boolean = json.decodeFromString<PinStatus>(call("GET", "/parental/pin")).set

// pin "" removes it. The administrator's own password (and code, with two-factor sign-in) goes with it.
suspend fun Api.setParentPin(pin: String, current: String, code: String): Boolean =
    json.decodeFromString<PinStatus>(call("PUT", "/parental/pin", json.encodeToString(PinChange(pin, current, code)))).set

// A name and a picture, for oneself or for someone managed. Only what is given is changed.
suspend fun Api.saveLook(id: Long, displayName: String? = null, username: String? = null, avatar: String? = null): User =
    json.decodeFromString(call("PUT", "/users/$id/profile", json.encodeToString(LookChange(displayName, username, avatar))))

suspend fun Api.allGenres(): List<String> {
    val a = runCatching { json.decodeFromString<List<String>?>(call("GET", "/genres")).orEmpty() }.getOrDefault(emptyList())
    val b = runCatching { json.decodeFromString<List<String>?>(call("GET", "/shows/genres")).orEmpty() }.getOrDefault(emptyList())
    return (a + b).distinct().sorted()
}
