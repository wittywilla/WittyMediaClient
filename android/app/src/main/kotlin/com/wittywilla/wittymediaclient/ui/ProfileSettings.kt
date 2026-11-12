// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.text.format.DateFormat
import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.net.Access
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.Collection
import com.wittywilla.wittymediaclient.net.FEATURE_AVATARS
import com.wittywilla.wittymediaclient.net.FEATURE_SCREEN_TIME
import com.wittywilla.wittymediaclient.net.FEATURE_SWITCHES
import com.wittywilla.wittymediaclient.net.KindLimit
import com.wittywilla.wittymediaclient.net.Library
import com.wittywilla.wittymediaclient.net.ManagedUser
import com.wittywilla.wittymediaclient.net.Managing
import com.wittywilla.wittymediaclient.net.ParentalLists
import com.wittywilla.wittymediaclient.net.ProfileActivity
import com.wittywilla.wittymediaclient.net.ScreenTime
import com.wittywilla.wittymediaclient.net.ScreenTimeRules
import com.wittywilla.wittymediaclient.net.TimeOfDay
import com.wittywilla.wittymediaclient.net.accessDiff
import com.wittywilla.wittymediaclient.net.allGenres
import com.wittywilla.wittymediaclient.net.clearProfileActivity
import com.wittywilla.wittymediaclient.net.giveTime
import com.wittywilla.wittymediaclient.net.managedUsers
import com.wittywilla.wittymediaclient.net.parentPinSet
import com.wittywilla.wittymediaclient.net.parentalLists
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.profileActivity
import com.wittywilla.wittymediaclient.net.saveAccess
import com.wittywilla.wittymediaclient.net.saveLook
import com.wittywilla.wittymediaclient.net.setParentPin
import com.wittywilla.wittymediaclient.player.ScreenTimeWatch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.util.Calendar
import java.util.Date

// You → Profiles, as the app's own screens (the server's docs/PROFILES.md and ACCOUNTS.md): the profiles this
// account manages, each one's name and picture, its limits (what it sees, what it can do, screen time), its report,
// and the parents' PIN. The server decides who manages whom and applies every limit; these screens show what it
// allows and send what a parent changes, and only what they changed. They work with a finger and with a remote.

private fun words(e: Exception, s: Map<String, String>) = problemWords(e, s["errLost"].orEmpty())

private fun text(s: Map<String, String>, key: String, vararg values: Pair<String, Any>): String =
    values.fold(s[key].orEmpty()) { out, (name, value) -> out.replace("{$name}", value.toString()) }

private fun shownName(u: ManagedUser) = avatarName(u.displayName, u.name)

// "45 min", "1 h", "1 h 30 min".
fun durationWords(s: Map<String, String>, seconds: Int): String {
    val m = Math.round(seconds / 60f)
    return when {
        m < 60 -> text(s, "durMinutes", "n" to m)
        m % 60 == 0 -> text(s, "durHours", "n" to m / 60)
        else -> text(s, "durHoursMinutes", "h" to m / 60, "m" to m % 60)
    }
}

// An allowance a day: "No limit", "45 minutes", "1 hour", "2 hours", "1 h 30 min".
private fun allowanceWords(s: Map<String, String>, minutes: Int): String = when {
    minutes <= 0 -> s["timeNoLimit"].orEmpty()
    minutes < 60 -> text(s, "extraMinutes", "n" to minutes)
    minutes == 60 -> s["extraHour"].orEmpty()
    minutes % 60 == 0 -> text(s, "timeHours", "n" to minutes / 60)
    else -> text(s, "durHoursMinutes", "h" to minutes / 60, "m" to minutes % 60)
}

private fun ageWords(s: Map<String, String>, age: Int): String = when (age) {
    -1 -> s["ageEverything"].orEmpty()
    0 -> s["ageLittleKids"].orEmpty()
    7 -> s["ageKids7"].orEmpty()
    10 -> s["ageOlderKids"].orEmpty()
    13 -> s["ageTeens"].orEmpty()
    16 -> s["ageOlderTeens"].orEmpty()
    else -> text(s, "ageUpTo", "n" to age)
}

// A profile's limits in a line, for the list: "Kids 7+ · 2 libraries · screen time".
fun limitsSummary(s: Map<String, String>, u: ManagedUser): String {
    if (u.isAdmin) return s["limitsNone"].orEmpty()
    val a = u.access ?: return s["limitsNone"].orEmpty()
    val parts = mutableListOf(ageWords(s, a.maxAge))
    if (a.libraries.isNotEmpty()) parts += text(s, if (a.libraries.size == 1) "sumLibrary" else "sumLibraries", "n" to a.libraries.size)
    if (!a.liveTv) parts += s["sumNoLiveTv"].orEmpty()
    if (a.kinds.isNotEmpty()) parts += s["sumKinds"].orEmpty()
    if (!a.time.empty) parts += s["sumScreenTime"].orEmpty()
    val off = a.off.filter { it != "editProfile" }
    if (off.isNotEmpty()) parts += text(s, if (off.size == 1) "sumOffOne" else "sumOff", "n" to off.size)
    if (!u.hasPassword) parts += s["sumNoPassword"].orEmpty()
    return parts.filter { it.isNotEmpty() }.joinToString(" · ")
}

private fun roleWords(s: Map<String, String>, u: ManagedUser) = s[roleKey(u.isAdmin, u.kind)].orEmpty()

@Composable
private fun SectionHint(text: String) {
    if (text.isEmpty()) return
    Text(text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, modifier = Modifier.padding(horizontal = LocalMetrics.current.u(16)))
}

// The list: you, then everyone you manage, then what only an administrator has.
@Composable
fun ProfilesScreen(nav: Nav, s: Map<String, String>) {
    val me = nav.me ?: run { Screen { Loading() }; return }
    val api = nav.app.api
    var users by remember { mutableStateOf(nav.remembered<List<ManagedUser>>("managed-users")) }
    var pinSet by remember { mutableStateOf(nav.remembered<Boolean>("parents-pin")) }
    var problem by remember { mutableStateOf("") }
    LaunchedEffect(Unit) {
        try {
            users = api.managedUsers().also { nav.remember("managed-users", it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem = words(e, s)
        }
        if (me.isAdmin) runCatching { api.parentPinSet() }.getOrNull()?.let { pinSet = it; nav.remember("parents-pin", it) }
    }
    val limits = ScreenTimeWatch.limits
    val others = users?.filter { it.id != me.id }
    SettingsPage(nav, s["rowProfiles"].orEmpty(), s[if (me.isAdmin) "profilesHintAdmin" else "profilesHint"].orEmpty()) {
        Problem(problem, Modifier.fillMaxWidth())
        val mine = buildList {
            add(
                GroupRow(
                    avatarName(me.displayName, me.name), onClick = { nav.push(Route.You(YouNative.Names)) }, detail = s["rowNames"].orEmpty(),
                    leading = { ProfileFace(avatarName(me.displayName, me.name), me.avatar, LocalMetrics.current.u(32)) }, focusKey = "profiles-me", requestFocus = true,
                ),
            )
            if (nav.has(FEATURE_AVATARS) && Managing.ownLook(me.isAdmin, limits)) {
                add(GroupRow(s["changePicture"].orEmpty(), onClick = { nav.push(HouseholdRoute(HouseholdScreen.Look(me.id))) }, icon = Symbols.Person, tint = Color(0xFF0A6FB8), focusKey = "profiles-my-picture"))
            }
        }
        GroupedList(s["profilesYours"].orEmpty(), mine)
        if (me.isAdmin) SettingsSlotRows(nav, "people.profile")
        when {
            others == null -> if (problem.isEmpty()) Note(s["loading"].orEmpty(), busy = true)
            others.isEmpty() -> Note(s[if (limits?.limited == true) "profilesNoneLimited" else "profilesNone"].orEmpty())
            else -> others.forEach { u ->
                val name = shownName(u)
                GroupedList(
                    "$name · ${roleWords(s, u)}",
                    buildList {
                        if (Managing.mayRename(me.id, u)) {
                            add(
                                GroupRow(
                                    s["profileLook"].orEmpty(), onClick = { nav.push(HouseholdRoute(HouseholdScreen.Look(u.id))) },
                                    detail = if (showsUsername(u.displayName, u.name)) text(s, "profileSignsInAs", "name" to u.name) else "",
                                    leading = { ProfileFace(name, u.avatar, LocalMetrics.current.u(32)) }, focusKey = "look-${u.id}",
                                ),
                            )
                        }
                        if (Managing.mayLimit(me.id, u)) {
                            add(GroupRow(s["profileLimits"].orEmpty(), onClick = { nav.push(HouseholdRoute(HouseholdScreen.Limits(u.id))) }, icon = Symbols.ShieldLock, tint = Color(0xFF2E7D3C), detail = limitsSummary(s, u), focusKey = "limits-${u.id}"))
                            add(GroupRow(s["profileReport"].orEmpty(), onClick = { nav.push(HouseholdRoute(HouseholdScreen.Report(u.id))) }, icon = Symbols.Activity, tint = Color(0xFF99690A), detail = s["profileReportHint"].orEmpty(), focusKey = "report-${u.id}"))
                        } else if (u.isAdmin) {
                            add(GroupRow(s["limitsNone"].orEmpty(), detail = s["limitsAdminHint"].orEmpty()))
                        }
                    },
                )
            }
        }
        if (me.isAdmin) {
            GroupedList(
                s["parentsPinTitle"].orEmpty(),
                listOf(
                    GroupRow(
                        s["parentsPinTitle"].orEmpty(), onClick = { nav.push(HouseholdRoute(HouseholdScreen.ParentsPin)) }, icon = Symbols.Key, tint = Color(0xFF3E5BD0),
                        value = pinSet?.let { s[if (it) "parentsPinIsSet" else "parentsPinNotSet"] }.orEmpty(), focusKey = "parents-pin",
                    ),
                ),
            )
        }
        // Adding and removing profiles and their passwords stay on the server's own page.
        val more = s["profilesOnServer"].orEmpty()
        GroupedList(
            "",
            listOf(
                GroupRow(
                    more, onClick = { nav.push(if (nav.app.isTv) Route.OnPhone(more, USERS_PAGE) else Route.Page(USERS_PAGE, s["rowProfiles"].orEmpty())) },
                    icon = Symbols.Family, tint = Color(0xFFB8500D), detail = s["profilesOnServerHint"].orEmpty(), focusKey = "profiles-server",
                ),
            ),
        )
    }
}

private const val USERS_PAGE = "/settings/users"
private const val SAVED_SHOWN_MS = 2000L

// Loads the person a screen is about, from the list the server lets this account manage. A person who isn't in
// it isn't theirs to manage, and the screen says so instead of offering anything.
@Composable
private fun rememberManaged(nav: Nav, s: Map<String, String>, userId: Long, problem: (String) -> Unit): ManagedUser? {
    var user by remember { mutableStateOf(nav.remembered<List<ManagedUser>>("managed-users")?.firstOrNull { it.id == userId }) }
    LaunchedEffect(userId) {
        try {
            val list = nav.app.api.managedUsers()
            nav.remember("managed-users", list)
            user = list.firstOrNull { it.id == userId }
            if (user == null) problem(s["profileNotYours"].orEmpty())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem(words(e, s))
        }
    }
    return user
}

// A name and a picture. One's own picture (the names are on Names), or all three for someone managed.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun LookScreen(nav: Nav, s: Map<String, String>, userId: Long) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val me = nav.me ?: run { Screen { Loading() }; return }
    val self = userId == me.id
    var problem by remember { mutableStateOf("") }
    val managed = if (self) null else rememberManaged(nav, s, userId) { problem = it }
    var lists by remember { mutableStateOf(nav.remembered<ParentalLists>("parental-lists")) }
    LaunchedEffect(Unit) { runCatching { nav.app.api.parentalLists() }.getOrNull()?.let { lists = it; nav.remember("parental-lists", it) } }
    val startName = if (self) me.displayName else managed?.displayName.orEmpty()
    val startUser = if (self) me.name else managed?.name.orEmpty()
    val startAvatar = if (self) me.avatar else managed?.avatar.orEmpty()
    var displayName by rememberSaveable(startName) { mutableStateOf(startName) }
    var username by rememberSaveable(startUser) { mutableStateOf(startUser) }
    var avatar by rememberSaveable(startAvatar) { mutableStateOf(startAvatar) }
    var busy by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }
    val pictures = nav.has(FEATURE_AVATARS)

    fun save() {
        if (busy) return
        if (!self && username.isBlank()) { problem = s["errUsernameEmpty"].orEmpty(); return }
        busy = true
        problem = ""
        scope.launch {
            try {
                val changed = nav.app.api.saveLook(
                    userId,
                    displayName = displayName.trim().takeIf { !self && it != startName },
                    username = username.trim().takeIf { !self && it != startUser },
                    avatar = avatar.takeIf { pictures && it != startAvatar },
                )
                if (self) nav.me = changed
                saved = true
                delay(SAVED_SHOWN_MS)
                nav.pop()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }

    val shown = avatarName(displayName.trim(), username.trim()).ifEmpty { "?" }
    val title = if (self) s["changePicture"].orEmpty() else text(s, "profileLookFor", "name" to (managed?.let(::shownName) ?: "…"))
    SettingsPage(nav, title, s[if (self) "pictureHint" else "profileLookHint"].orEmpty()) {
        if (!self && managed == null) {
            if (problem.isEmpty()) Note(s["loading"].orEmpty(), busy = true) else Problem(problem, Modifier.fillMaxWidth())
            return@SettingsPage
        }
        ProfileFace(shown, avatar, metrics.u(if (metrics.tv) 120 else 88), if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
        if (!self) {
            WittyField(displayName, { displayName = it; problem = "" }, s["profileNameLabel"].orEmpty(), icon = Symbols.Badge, imeAction = ImeAction.Next, maxLength = 60)
            WittyField(username, { username = it; problem = "" }, s["usernameLabel"].orEmpty(), kind = FieldKind.Username, icon = Symbols.Person, imeAction = ImeAction.Done, maxLength = 40)
            SectionHint(s["profileUsernameHint"].orEmpty())
        }
        if (pictures) {
            val chosen = parseAvatar(avatar)
            val size = metrics.u(if (metrics.tv) 88 else 56)
            Text(s["pictureTitle"].orEmpty(), color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, modifier = Modifier.semantics { heading() })
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(metrics.u(12)), verticalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                PictureChoice(s["pictureInitial"].orEmpty(), chosen == null, { avatar = "" }, "picture-none", requestFocus = metrics.tv && chosen == null) { Avatar(shown, size) }
                offeredAvatars(lists?.avatars.orEmpty()).forEach { name ->
                    val on = chosen?.name == name
                    PictureChoice(avatarLabel(name), on, { avatar = withPicture(avatar, name) }, "picture-$name", requestFocus = metrics.tv && on) {
                        ProfileFace(shown, withPicture(avatar, name), size)
                    }
                }
            }
            if (chosen != null) {
                Text(s["pictureColour"].orEmpty(), color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section, modifier = Modifier.semantics { heading() })
                FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(metrics.u(12)), verticalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                    offeredColours(lists?.avatarColours.orEmpty()).forEach { colour ->
                        PictureChoice(avatarLabel(colour), chosen.colour == colour, { avatar = withColour(avatar, colour) }, "colour-$colour") {
                            Box(
                                Modifier
                                    .size(metrics.u(if (metrics.tv) 56 else 40))
                                    .clip(CircleShape)
                                    .background(Color(AVATAR_COLOURS[AVATAR_COLOUR_INDEX.getValue(colour)]))
                                    .border(1.dp, MaterialTheme.colorScheme.outline, CircleShape),
                            )
                        }
                    }
                }
            }
        }
        Problem(problem, Modifier.fillMaxWidth())
        if (saved) Done(s["saved"].orEmpty())
        else WittyButton(s["save"].orEmpty(), ::save, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true, focusKey = "look-save")
    }
}

// One picture or colour to choose: ringed in the accent when it's the one chosen, and said aloud by its name.
@Composable
private fun PictureChoice(label: String, on: Boolean, onClick: () -> Unit, focusKey: String, requestFocus: Boolean = false, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    val edge = if (on) LocalExtraColours.current.accentText else Color.Transparent
    Pressable(onClick, shape = metrics.corner(14), label = label, selected = on, focusKey = focusKey, requestFocus = requestFocus) {
        Box(Modifier.border(metrics.u(3).coerceAtLeast(2.dp), edge, metrics.corner(14)).padding(metrics.u(6))) { content() }
    }
}

private enum class LimitsTab { See, Do, Time }

// What one of the dialogs on the limits page is choosing.
private sealed interface Choosing {
    data class KindAge(val kind: String) : Choosing
    data object Libraries : Choosing
    data object HideGenres : Choosing
    data object OnlyGenres : Choosing
    data class InCollection(val id: Long, val name: String) : Choosing
    data class Exception(val show: Boolean, val id: Long, val title: String) : Choosing
    data class Allowance(val weekend: Boolean) : Choosing
}

private const val SAME = "same"
private const val ALLOW = "allow"
private const val BLOCK = "block"
private const val BY_RATING = ""

// A profile's limits: what it sees, what it can do, and screen time, as the web's three tabs.
@Composable
fun LimitsScreen(nav: Nav, s: Map<String, String>, userId: Long) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val api = nav.app.api
    val me = nav.me ?: run { Screen { Loading() }; return }
    var problem by remember { mutableStateOf("") }
    val user = rememberManaged(nav, s, userId) { problem = it }
    var original by remember { mutableStateOf<Access?>(null) }
    var a by remember { mutableStateOf(Access()) }
    var tab by rememberSaveable { mutableStateOf(LimitsTab.See) }
    var lists by remember { mutableStateOf(nav.remembered<ParentalLists>("parental-lists")) }
    var libraries by remember { mutableStateOf(emptyList<Library>()) }
    var genres by remember { mutableStateOf(emptyList<String>()) }
    var collections by remember { mutableStateOf(emptyList<Collection>()) }
    val titles = remember { mutableStateMapOf<String, String>() }
    var tags by remember { mutableStateOf("") }
    var query by remember { mutableStateOf("") }
    var found by remember { mutableStateOf(emptyList<Choosing.Exception>()) }
    var choosing by remember { mutableStateOf<Choosing?>(null) }
    var leaving by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var saved by remember { mutableStateOf(false) }

    // The limits as the server has them, once: what is changed here is compared with this when saving.
    LaunchedEffect(user?.id) {
        val read = user?.access ?: return@LaunchedEffect
        if (original == null) {
            original = read
            a = read
            tags = read.blockTags.joinToString(", ")
        }
    }
    LaunchedEffect(Unit) {
        runCatching { api.parentalLists() }.getOrNull()?.let { lists = it; nav.remember("parental-lists", it) }
        libraries = runCatching { api.libraries().distinctBy { it.id } }.getOrDefault(emptyList())
        genres = api.allGenres()
        // Only a collection that lists its titles can be a limit: one made from a rule holds whatever matches today.
        collections = runCatching { api.collections().filter { it.kind == "manual" && it.system.isEmpty() } }.getOrDefault(emptyList())
    }
    // Names for the titles already allowed or never allowed.
    LaunchedEffect(a.allowItems, a.blockItems, a.allowShows, a.blockShows) {
        (a.allowItems + a.blockItems).filter { "i$it" !in titles }.forEach { id -> runCatching { api.item(id).title }.getOrNull()?.let { titles["i$id"] = it } }
        (a.allowShows + a.blockShows).filter { "s$it" !in titles }.forEach { id -> runCatching { api.show(id).show.title }.getOrNull()?.let { titles["s$id"] = it } }
    }
    LaunchedEffect(query) {
        val q = query.trim()
        if (q.length < 2) { found = emptyList(); return@LaunchedEffect }
        delay(SEARCH_PAUSE_MS)
        val shows = runCatching { api.searchShows(q, SEARCH_MOST).shows }.getOrDefault(emptyList())
        val items = runCatching { api.searchItems(q, SEARCH_MOST).items }.getOrDefault(emptyList()).filter { it.showId == null }
        found = shows.map { Choosing.Exception(true, it.id, text(s, "exceptionShow", "title" to it.title)) } +
            items.map { Choosing.Exception(false, it.id, it.title + (it.year?.let { y -> " ($y)" } ?: "")) }
    }

    val current = a.copy(
        blockTags = tags.split(',').map { it.trim() }.filter { it.isNotEmpty() },
        time = a.time.copy(from = TimeOfDay.tidy(a.time.from), schoolNightUntil = TimeOfDay.tidy(a.time.schoolNightUntil), weekendUntil = TimeOfDay.tidy(a.time.weekendUntil)),
    )
    val changed = original?.let { accessDiff(it, current).isNotEmpty() } == true

    fun save() {
        val from = original ?: return
        if (busy) return
        TimeOfDay.problem(current.time)?.let { problem = s[it].orEmpty(); tab = LimitsTab.Time; return }
        val change = accessDiff(from, current)
        busy = true
        problem = ""
        scope.launch {
            try {
                if (change.isNotEmpty()) {
                    val now = api.saveAccess(userId, change).access ?: current
                    original = now
                    a = now
                    tags = now.blockTags.joinToString(", ")
                }
                saved = true
                delay(SAVED_SHOWN_MS)
                saved = false
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }

    fun exception(of: Choosing.Exception, how: String) {
        titles[(if (of.show) "s" else "i") + of.id] = of.title
        a = if (of.show) {
            a.copy(allowShows = (a.allowShows - of.id).let { if (how == ALLOW) it + of.id else it }, blockShows = (a.blockShows - of.id).let { if (how == BLOCK) it + of.id else it })
        } else {
            a.copy(allowItems = (a.allowItems - of.id).let { if (how == ALLOW) it + of.id else it }, blockItems = (a.blockItems - of.id).let { if (how == BLOCK) it + of.id else it })
        }
        query = ""
    }

    val name = user?.let(::shownName) ?: "…"
    val systems = lists?.systems.orEmpty()
    val kinds = lists?.kinds.orEmpty()
    fun kindLabel(kind: String) = s["kind_$kind"] ?: avatarLabel(kind)
    fun ageChoice(kind: String?, age: Int): String {
        if (age < 0) return s["ageNone"].orEmpty()
        val allowed = if (kind == null) Managing.allowedOverall(systems, age) else Managing.allowedAt(systems, kind, age)
        val words = if (age == 0) s["ageForEveryone"].orEmpty() else text(s, "ageUpTo", "n" to age)
        return if (allowed.isEmpty()) words else "$words ($allowed)"
    }
    val toggle: @Composable (Boolean) -> Unit = { Toggle(it) }

    SettingsPage(nav, text(s, "limitsFor", "name" to name), s["limitsHint"].orEmpty(), onBack = { if (changed) leaving = true else nav.pop() }) {
        if (user == null || original == null) {
            if (problem.isEmpty()) Note(s["loading"].orEmpty(), busy = true) else Problem(problem, Modifier.fillMaxWidth())
            return@SettingsPage
        }
        if (!Managing.mayLimit(me.id, user)) {
            Note(s["profileNotYours"].orEmpty())
            return@SettingsPage
        }
        Row(Modifier.fillMaxWidth().remoteRow(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
            listOf(LimitsTab.See to "limitsTabSee", LimitsTab.Do to "limitsTabDo", LimitsTab.Time to "limitsTabTime").forEachIndexed { i, (which, key) ->
                WittyButton(
                    s[key].orEmpty(), { tab = which }, Modifier.weight(1f), kind = if (tab == which) ButtonKind.Primary else ButtonKind.Secondary,
                    focusKey = "limits-tab-$i", requestFocus = i == 0,
                )
            }
        }
        when (tab) {
            LimitsTab.See -> {
                val levels = if (a.maxAge in Managing.AGE_LEVELS) Managing.AGE_LEVELS else (Managing.AGE_LEVELS + a.maxAge)
                GroupedList(
                    s["limitsAge"].orEmpty(),
                    levels.map { age ->
                        GroupRow(
                            ageWords(s, age), onClick = { a = a.copy(maxAge = age) }, chevron = false, selected = a.maxAge == age, focusKey = "age-$age",
                            detail = if (age < 0) s["ageNone"].orEmpty() else Managing.allowedOverall(systems, age), trailing = { CheckMark(a.maxAge == age) },
                        )
                    } + listOfNotNull(
                        if (a.maxAge >= 0) GroupRow(s["limitsUnrated"].orEmpty(), onClick = { a = a.copy(allowUnrated = !a.allowUnrated) }, detail = s["limitsUnratedHint"].orEmpty(), chevron = false, focusKey = "unrated", trailing = { toggle(a.allowUnrated) }) else null,
                    ),
                )
                if (kinds.isNotEmpty()) {
                    GroupedList(
                        s["limitsKinds"].orEmpty(),
                        kinds.flatMap { kind ->
                            val mine = a.kinds[kind]
                            listOfNotNull(
                                GroupRow(kindLabel(kind), onClick = { choosing = Choosing.KindAge(kind) }, detail = if (mine == null) s["kindSame"].orEmpty() else ageChoice(kind, mine.maxAge), focusKey = "kind-$kind"),
                                if (mine != null && mine.maxAge >= 0) {
                                    GroupRow(
                                        text(s, "kindUnrated", "kind" to kindLabel(kind)), onClick = { a = a.copy(kinds = a.kinds + (kind to mine.copy(allowUnrated = !mine.allowUnrated))) },
                                        chevron = false, focusKey = "kind-unrated-$kind", trailing = { toggle(mine.allowUnrated) },
                                    )
                                } else {
                                    null
                                },
                            )
                        },
                    )
                    SectionHint(s["limitsKindsHint"].orEmpty())
                }
                GroupedList(
                    s["limitsLists"].orEmpty(),
                    listOfNotNull(
                        GroupRow(s["limitsLibraries"].orEmpty(), onClick = { choosing = Choosing.Libraries }, value = if (a.libraries.isEmpty()) s["limitsAll"].orEmpty() else a.libraries.size.toString(), detail = s["limitsLibrariesHint"].orEmpty(), focusKey = "libraries"),
                        if (genres.isNotEmpty() || a.blockGenres.isNotEmpty()) GroupRow(s["limitsHideGenres"].orEmpty(), onClick = { choosing = Choosing.HideGenres }, value = a.blockGenres.size.takeIf { it > 0 }?.toString().orEmpty(), focusKey = "hide-genres") else null,
                        if (genres.isNotEmpty() || a.onlyGenres.isNotEmpty()) GroupRow(s["limitsOnlyGenres"].orEmpty(), onClick = { choosing = Choosing.OnlyGenres }, value = a.onlyGenres.size.takeIf { it > 0 }?.toString().orEmpty(), detail = s["limitsOnlyGenresHint"].orEmpty(), focusKey = "only-genres") else null,
                    ),
                )
                GroupedList(
                    s["limitsCollections"].orEmpty(),
                    collections.map { c ->
                        val how = when (c.id) {
                            in a.blockCollections -> "exceptionNever"
                            in a.allowCollections -> "exceptionAlways"
                            else -> "exceptionByRating"
                        }
                        GroupRow(c.name, onClick = { choosing = Choosing.InCollection(c.id, c.name) }, value = s[how].orEmpty(), detail = text(s, if (c.count == 1) "collectionTitle" else "collectionTitles", "n" to c.count), focusKey = "collection-${c.id}")
                    },
                )
                SectionHint(s[if (collections.isEmpty()) "limitsCollectionsNone" else "limitsCollectionsHint"].orEmpty())
                WittyField(tags, { tags = it }, s["limitsTags"].orEmpty(), imeAction = ImeAction.Done, maxLength = 2000)
                SectionHint(s["limitsTagsHint"].orEmpty())
                val exceptions = a.allowShows.map { Triple(true, it, true) } + a.allowItems.map { Triple(false, it, true) } +
                    a.blockShows.map { Triple(true, it, false) } + a.blockItems.map { Triple(false, it, false) }
                GroupedList(
                    s["limitsExceptions"].orEmpty(),
                    exceptions.map { (show, id, allowed) ->
                        val title = titles[(if (show) "s" else "i") + id] ?: "…"
                        GroupRow(title, onClick = { choosing = Choosing.Exception(show, id, title) }, value = s[if (allowed) "exceptionAlways" else "exceptionNever"].orEmpty(), focusKey = "exception-$show-$id")
                    },
                )
                SectionHint(s["limitsExceptionsHint"].orEmpty())
                WittyField(query, { query = it }, s["limitsExceptionsSearch"].orEmpty(), icon = Symbols.Search, imeAction = ImeAction.Search, maxLength = 80)
                if (found.isNotEmpty()) {
                    GroupedList("", found.map { f -> GroupRow(f.title, onClick = { choosing = f }, focusKey = "found-${f.show}-${f.id}") })
                }
            }
            LimitsTab.Do -> {
                val grownUp = user.kind == "adult"
                // Only the switches this server has.
                val known = lists?.features.orEmpty()
                GroupedList(
                    s["limitsTabDo"].orEmpty(),
                    FEATURE_SWITCHES.filter { known.isEmpty() || it.id in known }.map { f ->
                        val never = f.adultOnly && !grownUp
                        val hint = when {
                            never -> s["featureAdultOnly"].orEmpty()
                            !grownUp && f.id == "comments" -> s["feature_comments_kids"].orEmpty()
                            else -> s["feature_${f.id}_hint"].orEmpty()
                        }
                        GroupRow(
                            s["feature_${f.id}"].orEmpty(), onClick = if (never) null else ({ a = a.with(f.id, !a.can(f.id)) }), detail = hint, chevron = false,
                            focusKey = "feature-${f.id}", trailing = { toggle(!never && a.can(f.id)) },
                        )
                    },
                )
                GroupedList(
                    s["liveTvTab"].orEmpty(),
                    listOf(
                        GroupRow(s["liveTvTab"].orEmpty(), onClick = { a = a.copy(liveTv = !a.liveTv) }, chevron = false, focusKey = "live-tv", trailing = { toggle(a.liveTv) }),
                        GroupRow(s["limitsLibraryChannels"].orEmpty(), onClick = if (a.liveTv) ({ a = a.copy(libraryChannels = !a.libraryChannels) }) else null, chevron = false, focusKey = "library-channels", trailing = { toggle(a.liveTv && a.libraryChannels) }),
                        GroupRow(s["limitsTunerChannels"].orEmpty(), onClick = if (a.liveTv) ({ a = a.copy(tunerChannels = !a.tunerChannels) }) else null, chevron = false, focusKey = "tuner-channels", trailing = { toggle(a.liveTv && a.tunerChannels) }),
                    ),
                )
            }
            LimitsTab.Time -> {
                if (!nav.has(FEATURE_SCREEN_TIME)) {
                    Note(s["timeNotHere"].orEmpty())
                } else {
                    SectionHint(s["timeHint"].orEmpty())
                    GroupedList(
                        s["timeAllowance"].orEmpty(),
                        listOf(
                            GroupRow(s["timeSchoolDays"].orEmpty(), onClick = { choosing = Choosing.Allowance(false) }, value = allowanceWords(s, a.time.schoolDayMinutes), detail = s["timeSchoolDaysHint"].orEmpty(), focusKey = "time-school"),
                            GroupRow(s["timeWeekends"].orEmpty(), onClick = { choosing = Choosing.Allowance(true) }, value = allowanceWords(s, a.time.weekendMinutes), detail = s["timeWeekendsHint"].orEmpty(), focusKey = "time-weekend"),
                        ),
                    )
                    WittyField(a.time.from, { a = a.copy(time = a.time.copy(from = it.take(5))); problem = "" }, s["timeFrom"].orEmpty(), imeAction = ImeAction.Next, maxLength = 5)
                    SectionHint(s["timeFromHint"].orEmpty())
                    WittyField(a.time.schoolNightUntil, { a = a.copy(time = a.time.copy(schoolNightUntil = it.take(5))); problem = "" }, s["timeSchoolNight"].orEmpty(), imeAction = ImeAction.Next, maxLength = 5)
                    SectionHint(s["timeSchoolNightHint"].orEmpty())
                    WittyField(a.time.weekendUntil, { a = a.copy(time = a.time.copy(weekendUntil = it.take(5))); problem = "" }, s["timeWeekendNight"].orEmpty(), imeAction = ImeAction.Done, maxLength = 5)
                    SectionHint(s["timeHolidays"].orEmpty())
                }
            }
        }
        Problem(problem, Modifier.fillMaxWidth())
        if (saved) Done(s["limitsSaved"].orEmpty())
        else WittyButton(s["limitsSave"].orEmpty(), ::save, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, enabled = changed, tall = true, focusKey = "limits-save")
    }

    when (val c = choosing) {
        null -> Unit
        is Choosing.KindAge -> {
            val mine = a.kinds[c.kind]
            val ages = Managing.agesFor(systems, c.kind, mine?.maxAge)
            PickDialog(
                kindLabel(c.kind),
                listOf(Pick(SAME, s["kindSame"].orEmpty())) + ages.map { Pick(it.toString(), ageChoice(c.kind, it)) } + Pick("-1", s["ageNone"].orEmpty()),
                mine?.maxAge?.toString() ?: SAME,
                onPick = { id ->
                    a = if (id == SAME) a.copy(kinds = a.kinds - c.kind)
                    else a.copy(kinds = a.kinds + (c.kind to KindLimit(id.toInt(), mine?.allowUnrated ?: a.allowUnrated)))
                },
                onClose = { choosing = null },
            )
        }
        Choosing.Libraries -> MultiPickDialog(s["limitsLibraries"].orEmpty(), s["limitsLibrariesHint"].orEmpty(), libraries.map { Pick(it.id.toString(), it.name) }, a.libraries.map { it.toString() }.toSet()) { now ->
            // The ones this app can't list (a library since hidden from this account) stay as they were.
            val listed = libraries.map { it.id }.toSet()
            a = a.copy(libraries = a.libraries.filter { it !in listed } + libraries.map { it.id }.filter { it.toString() in now })
            choosing = null
        }
        Choosing.HideGenres -> MultiPickDialog(s["limitsHideGenres"].orEmpty(), "", (genres + a.blockGenres).distinct().map { Pick(it, it) }, a.blockGenres.toSet()) { now ->
            a = a.copy(blockGenres = (genres + a.blockGenres).distinct().filter { it in now })
            choosing = null
        }
        Choosing.OnlyGenres -> MultiPickDialog(s["limitsOnlyGenres"].orEmpty(), s["limitsOnlyGenresHint"].orEmpty(), (genres + a.onlyGenres).distinct().map { Pick(it, it) }, a.onlyGenres.toSet()) { now ->
            a = a.copy(onlyGenres = (genres + a.onlyGenres).distinct().filter { it in now })
            choosing = null
        }
        is Choosing.InCollection -> PickDialog(
            c.name,
            listOf(Pick(BY_RATING, s["exceptionByRating"].orEmpty()), Pick(ALLOW, s["exceptionAlways"].orEmpty()), Pick(BLOCK, s["exceptionNever"].orEmpty())),
            when (c.id) {
                in a.blockCollections -> BLOCK
                in a.allowCollections -> ALLOW
                else -> BY_RATING
            },
            onPick = { how ->
                a = a.copy(
                    allowCollections = (a.allowCollections - c.id).let { if (how == ALLOW) it + c.id else it },
                    blockCollections = (a.blockCollections - c.id).let { if (how == BLOCK) it + c.id else it },
                )
            },
            onClose = { choosing = null },
        )
        is Choosing.Exception -> {
            val now = when {
                c.show && c.id in a.allowShows || !c.show && c.id in a.allowItems -> ALLOW
                c.show && c.id in a.blockShows || !c.show && c.id in a.blockItems -> BLOCK
                else -> BY_RATING
            }
            PickDialog(
                c.title,
                listOf(Pick(ALLOW, s["exceptionAlways"].orEmpty(), s["exceptionAlwaysHint"].orEmpty()), Pick(BLOCK, s["exceptionNever"].orEmpty(), s["exceptionNeverHint"].orEmpty()), Pick(BY_RATING, s["exceptionByRating"].orEmpty())),
                now, onPick = { how -> exception(c, how) }, onClose = { choosing = null },
            )
        }
        is Choosing.Allowance -> {
            val minutes = if (c.weekend) a.time.weekendMinutes else a.time.schoolDayMinutes
            PickDialog(
                s[if (c.weekend) "timeWeekends" else "timeSchoolDays"].orEmpty(), Managing.allowances(minutes).map { Pick(it.toString(), allowanceWords(s, it)) }, minutes.toString(),
                onPick = { id -> a = a.copy(time = if (c.weekend) a.time.copy(weekendMinutes = id.toInt()) else a.time.copy(schoolDayMinutes = id.toInt())) },
                onClose = { choosing = null },
            )
        }
    }
    if (leaving) {
        AskDialog(s["limitsLeave"].orEmpty(), s["limitsLeaveHint"].orEmpty(), s["limitsLeaveYes"].orEmpty(), s["limitsLeaveNo"].orEmpty(), onYes = { leaving = false; nav.pop() }, onNo = { leaving = false })
    }
}

private const val SEARCH_PAUSE_MS = 300L
private const val SEARCH_MOST = 6

// The report: today and more time, what they watched each day, and what was refused. The last two weeks.
@Composable
fun ReportScreen(nav: Nav, s: Map<String, String>, userId: Long) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = nav.app.api
    var problem by remember { mutableStateOf("") }
    val user = rememberManaged(nav, s, userId) { problem = it }
    var report by remember { mutableStateOf<ProfileActivity?>(null) }
    var round by remember { mutableIntStateOf(0) }
    var given by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var clearing by remember { mutableStateOf(false) }
    val name = user?.let(::shownName) ?: "…"
    LaunchedEffect(round) {
        try {
            report = api.profileActivity(userId)
            problem = ""
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem = words(e, s)
        }
    }
    fun act(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        problem = ""
        scope.launch {
            try {
                block()
                round++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (!nav.handleExpired(e)) problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }
    fun dayWords(day: Int): String {
        val (y, m, d) = Managing.dayParts(day)
        val at = Calendar.getInstance().apply { clear(); set(y, m - 1, d) }.timeInMillis
        return DateUtils.formatDateTime(context, at, DateUtils.FORMAT_SHOW_WEEKDAY or DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_NO_YEAR)
    }
    fun eventWords(kind: String, title: String, detail: String): String = when (kind) {
        "blocked" -> text(s, "reportBlocked", "title" to title.ifEmpty { s["reportGone"].orEmpty() }) + if (detail.isNotEmpty()) " ($detail)" else ""
        "extra" -> text(s, "reportExtra", "n" to detail, "who" to if (title == "PIN") s["reportByPin"].orEmpty() else title)
        "time" -> text(s, "reportTime", "why" to (s["reportWhy_$detail"] ?: detail))
        "feature" -> text(s, "reportFeature", "what" to (s["feature_$detail"] ?: detail))
        else -> kind
    }
    SettingsPage(nav, text(s, "reportFor", "name" to name), s["reportHint"].orEmpty()) {
        val a = report
        if (a == null) {
            if (problem.isEmpty()) Note(s["loading"].orEmpty(), busy = true) else Problem(problem, Modifier.fillMaxWidth())
            return@SettingsPage
        }
        val st: ScreenTime = a.screenTime
        val today = if (st.allowanceSec >= 0) text(s, "reportUsedOf", "used" to durationWords(s, st.usedSec), "of" to durationWords(s, st.allowanceSec)) else text(s, "reportUsed", "used" to durationWords(s, st.usedSec))
        GroupedList(s["reportToday"].orEmpty(), listOf(GroupRow(today, detail = if (!st.allowed) st.message else "")))
        if (nav.has(FEATURE_SCREEN_TIME)) {
            Text(text(s, "reportGive", "name" to name), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, modifier = Modifier.padding(horizontal = metrics.u(16)))
            Row(Modifier.fillMaxWidth().remoteRow(), horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                ScreenTimeRules.EXTRA_CHOICES.forEachIndexed { i, m ->
                    val label = text(s, if (m == 60) "extraHour" else "extraMinutes", "n" to m)
                    WittyButton(label, { act { api.giveTime(userId, m); given = text(s, "reportGiven", "name" to name, "time" to label) } }, Modifier.weight(1f), enabled = !busy, focusKey = "give-$m", requestFocus = i == 0)
                }
            }
            if (given.isNotEmpty()) Done(given)
        }
        Problem(problem, Modifier.fillMaxWidth())
        val days = Managing.reportDays(a)
        if (days.isEmpty()) {
            GroupedList(s["reportWatched"].orEmpty(), listOf(GroupRow(s["reportNothing"].orEmpty(), detail = s["reportNothingHint"].orEmpty())))
        }
        days.forEach { day ->
            val total = a.days.firstOrNull { it.day == day }
            val caption = dayWords(day) + (total?.let { " · " + text(s, "reportScreen", "time" to durationWords(s, it.screenSec)) + if (it.extraSec > 0) ", " + text(s, "reportWithExtra", "time" to durationWords(s, it.extraSec)) else "" } ?: "")
            GroupedList(
                caption,
                a.watched.filter { it.day == day }.map { w ->
                    GroupRow((if (w.showTitle.isNotEmpty()) w.showTitle + ": " else "") + w.title.ifEmpty { s["reportGone"].orEmpty() }, value = durationWords(s, w.seconds.toInt()))
                }.ifEmpty { listOf(GroupRow(s["reportNoTitles"].orEmpty())) },
            )
        }
        GroupedList(
            s["reportRefused"].orEmpty(),
            a.events.map { e ->
                GroupRow(eventWords(e.kind, e.title, e.detail), detail = DateFormat.format("EEE ", Date(e.at * 1000)).toString() + DateFormat.getTimeFormat(context).format(Date(e.at * 1000)))
            }.ifEmpty { listOf(GroupRow(s["reportNothing"].orEmpty())) },
        )
        WittyButton(s["reportClear"].orEmpty(), { clearing = true }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, enabled = !busy, focusKey = "report-clear")
    }
    if (clearing) {
        AskDialog(
            text(s, "reportClearAsk", "name" to name), s["reportClearHint"].orEmpty(), s["reportClear"].orEmpty(), s["cancel"].orEmpty(),
            onYes = { clearing = false; given = ""; act { api.clearProfileActivity(userId) } }, onNo = { clearing = false },
        )
    }
}

// The parents' PIN: what a parent types on a child's device to give more time. Administrators set it, with their
// own password (and code, with two-factor sign-in), so a device left signed in isn't enough to choose it.
@Composable
fun ParentsPinScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    val api = nav.app.api
    val me = nav.me ?: run { Screen { Loading() }; return }
    var isSet by remember { mutableStateOf(nav.remembered<Boolean>("parents-pin")) }
    var pin by remember { mutableStateOf("") }
    var current by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    var done by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var wrong by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        try {
            isSet = api.parentPinSet().also { nav.remember("parents-pin", it) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (!nav.handleExpired(e)) problem = words(e, s)
        }
    }
    fun save(value: String) {
        if (busy) return
        busy = true
        problem = ""
        done = ""
        scope.launch {
            try {
                val now = api.setParentPin(value, current, code.trim())
                isSet = now
                nav.remember("parents-pin", now)
                pin = ""
                current = ""
                code = ""
                done = s[if (now) "parentsPinSaved" else "parentsPinRemoved"].orEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (nav.handleExpired(e)) return@launch
                // The password wasn't theirs: asked for again, as on every screen that asks for it.
                if (e.status == 403 || e.status == 401) { current = ""; code = ""; wrong++ }
                problem = words(e, s)
            } catch (e: Exception) {
                problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }
    SettingsPage(nav, s["parentsPinTitle"].orEmpty(), s["parentsPinHint"].orEmpty()) {
        if (!me.isAdmin) {
            Note(s["parentsPinAdminOnly"].orEmpty())
            return@SettingsPage
        }
        Note(s[if (isSet == true) "parentsPinStateSet" else "parentsPinStateNone"].orEmpty(), busy = isSet == null && problem.isEmpty())
        WittyField(pin, { pin = ScreenTimeRules.typedPin(it); problem = ""; done = "" }, s[if (isSet == true) "parentsPinNew" else "parentsPinLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Key, imeAction = ImeAction.Next, maxLength = 12)
        SectionHint(s["parentsPinDigits"].orEmpty())
        WittyField(current, { current = it; problem = "" }, s["yourPasswordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password, imeAction = if (me.twoFactor) ImeAction.Next else ImeAction.Done, isError = wrong > 0 && problem.isNotEmpty(), shake = wrong)
        if (me.twoFactor) WittyField(code, { code = it.take(32); problem = "" }, s["switchCodeLabel"].orEmpty(), icon = Symbols.ShieldLock, imeAction = ImeAction.Done, maxLength = 32)
        Problem(problem, Modifier.fillMaxWidth())
        if (done.isNotEmpty()) Done(done)
        val confirmed = current.isNotEmpty() && (!me.twoFactor || code.isNotBlank())
        WittyButton(s[if (isSet == true) "parentsPinChange" else "parentsPinSet"].orEmpty(), { save(pin) }, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, enabled = ScreenTimeRules.pinReady(pin) && confirmed, tall = true, focusKey = "pin-save")
        if (isSet == true) WittyButton(s["parentsPinRemove"].orEmpty(), { save("") }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, enabled = confirmed && !busy, tall = true, focusKey = "pin-remove")
    }
}
