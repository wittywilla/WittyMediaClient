// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.wittywilla.wittymediaclient.MainActivity
import com.wittywilla.wittymediaclient.net.Note
import com.wittywilla.wittymediaclient.net.NoteChoice
import com.wittywilla.wittymediaclient.net.NoteKinds
import com.wittywilla.wittymediaclient.net.clearNotes
import com.wittywilla.wittymediaclient.net.markNotesRead
import com.wittywilla.wittymediaclient.net.noteChoices
import com.wittywilla.wittymediaclient.net.noteCount
import com.wittywilla.wittymediaclient.net.notes
import com.wittywilla.wittymediaclient.net.setNoteChoices
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// The bell (the server's docs/NOTIFICATIONS.md): beside the top of every phone page and at the end of a TV's bar, with
// how many notifications are unread; its list is a screen of its own. One small request a minute, and only while the
// app is in front. On a phone, the phone's own notifications may show new ones too, while the app is open: off until
// the person turns it on, and Android asks them first.

object NoteWatch {
    var unread by mutableIntStateOf(0)
    var latest by mutableLongStateOf(0L)
}

private const val POLL_MS = 60_000L
private const val PREFS = "notes"
private const val SYSTEM_KEY = "system"
private const val CHANNEL = "notes"

@Composable
fun NoteWatcher(nav: Nav) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val api = nav.app.api
    LaunchedEffect(api.token, owner) {
        NoteWatch.unread = 0
        NoteWatch.latest = 0
        if (api.token.isEmpty()) return@LaunchedEffect
        var first = true
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                runCatching { api.noteCount() }.onSuccess { c ->
                    val before = NoteWatch.latest
                    NoteWatch.unread = c.unread
                    NoteWatch.latest = c.latest
                    if (!first && c.latest > before && !nav.app.isTv && SystemNotes.on(context)) {
                        runCatching { api.notes(limit = 10) }.getOrNull()?.notes?.let { SystemNotes.post(context, NoteKinds.fresh(it, before)) }
                    }
                    first = false
                }
                delay(POLL_MS)
            }
        }
    }
}

// Where a notification's link leads in this app: a show's own screen, the TV's recordings, or the server's page.
fun noteRoute(nav: Nav, link: String, title: String): Route? {
    val path = NoteKinds.safeLink(link).ifEmpty { return null }
    path.removePrefix("/show/").toLongOrNull()?.takeIf { path.startsWith("/show/") }?.let { return Route.Show(it) }
    if (nav.app.isTv && path.startsWith("/tv/recordings")) return TvRoute(TvScreen.Recordings)
    return if (nav.app.isTv) Route.OnPhone(title, path) else Route.Page(path, title)
}

// The phone's top bar: the bell, a 40 circle of the page colour at 70% as Back is, with the count in the accent.
@Composable
fun NoteBell(nav: Nav) {
    val page = MaterialTheme.colorScheme.background
    val n = NoteWatch.unread
    val label = if (n > 0) "Notifications, $n unread" else "Notifications"
    Pressable({ nav.push(Route.Notes) }, Modifier.size(44.dp), shape = CircleShape, label = label, pressScale = 0.975f, ring = false) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Box(Modifier.size(40.dp).clip(CircleShape).background(page.copy(alpha = 0.7f)), contentAlignment = Alignment.Center) {
                Icon(WebIcons.Bell, contentDescription = null, tint = MaterialTheme.colorScheme.onBackground, modifier = Modifier.size(20.dp))
            }
            if (n > 0) CountDot(n, Modifier.align(Alignment.TopEnd), 17.dp, 10.sp)
        }
    }
}

@Composable
fun CountDot(n: Int, modifier: Modifier, size: Dp, text: androidx.compose.ui.unit.TextUnit) {
    Box(
        modifier.heightIn(min = size).widthIn(min = size).clip(RoundedCornerShape(50)).background(MaterialTheme.colorScheme.primary).padding(horizontal = 4.dp),
        contentAlignment = Alignment.Center,
    ) { Text(if (n > 99) "99+" else n.toString(), color = MaterialTheme.colorScheme.onPrimary, fontSize = text, fontWeight = FontWeight.Bold, maxLines = 1) }
}

// The list: newest first, unread ones marked, each opening what it's about. On a TV the remote moves through it; there are
// no keys shown and no settings to change here (Settings is on a phone or a computer, as the website's TV mode says).
@Composable
fun NotesScreen(nav: Nav) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val scope = rememberCoroutineScope()
    val api = nav.app.api
    var list by remember { mutableStateOf<List<Note>?>(null) }
    var more by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf("") }
    suspend fun load(older: Boolean = false) {
        runCatching { api.notes(before = if (older) list?.lastOrNull()?.id ?: 0 else 0) }
            .onSuccess { r ->
                val got = r.notes.orEmpty()
                list = if (older) list.orEmpty() + got else got
                more = got.size == 30
                NoteWatch.unread = r.unread
                NoteWatch.latest = r.latest
                error = ""
            }
            .onFailure { error = it.message ?: "The notifications couldn't be read." }
    }
    LaunchedEffect(Unit) { load() }
    fun act(f: suspend () -> Unit) { scope.launch { runCatching { f() }.onFailure { error = it.message ?: "That didn't work." } } }
    Screen {
        LazyColumn(
            Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = metrics.gutter),
            verticalArrangement = Arrangement.spacedBy(Space.S3),
        ) {
            item { Spacer(Space.S4) }
            item { Heading("Notifications") }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
                    ActionButton("Back", nav::back, requestFocus = list.isNullOrEmpty())
                    if (!list.isNullOrEmpty()) {
                        ActionButton("Mark all read", { act { api.markNotesRead(); list = list?.map { it.copy(read = true) }; NoteWatch.unread = 0 } }, enabled = NoteWatch.unread > 0)
                        ActionButton("Clear all", { act { api.clearNotes(); list = emptyList(); more = false; NoteWatch.unread = 0 } })
                    }
                }
            }
            if (error.isNotEmpty()) item { Text(error, color = scheme.error, style = MaterialTheme.typography.bodyMedium) }
            val shown = list
            when {
                shown == null -> item { Text("Loading…", color = scheme.onSurfaceVariant) }
                shown.isEmpty() -> item {
                    Column(verticalArrangement = Arrangement.spacedBy(Space.S2)) {
                        Text("Nothing new", style = MaterialTheme.typography.titleMedium, color = scheme.onBackground)
                        Text("New episodes, finished recordings and updates show up here.", color = scheme.onSurfaceVariant)
                    }
                }
                else -> items(shown, key = { it.id }) { note ->
                    NoteRow(note, first = note == shown.first(),
                        open = {
                            if (!note.read) act { api.markNotesRead(listOf(note.id)); list = list?.map { if (it.id == note.id) it.copy(read = true) else it }; NoteWatch.unread = maxOf(0, NoteWatch.unread - 1) }
                            noteRoute(nav, note.link, note.title)?.let { nav.push(it) }
                        },
                        clear = { act { val c = api.clearNotes(note.id); list = list?.filter { it.id != note.id }; NoteWatch.unread = c.unread } })
                }
            }
            if (more) item { ActionButton("Show more", { act { load(older = true) } }) }
            if (!nav.app.isTv) item { NoteChoicesPanel(nav) }
            item { Spacer(Space.S6) }
        }
    }
}

@Composable
private fun Spacer(h: Dp) = androidx.compose.foundation.layout.Spacer(Modifier.padding(top = h))

@Composable
private fun NoteRow(note: Note, first: Boolean, open: () -> Unit, clear: () -> Unit) {
    val scheme = MaterialTheme.colorScheme
    val metrics = LocalMetrics.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S2)) {
        Pressable(
            open, Modifier.weight(1f), fill = scheme.surfaceVariant,
            label = note.title + (if (note.body.isNotEmpty()) ". " + note.body else "") + if (note.read) "" else ", unread",
            requestFocus = first, focusKey = "note-${note.id}",
        ) { active ->
            val ink = if (active && metrics.focusFill) scheme.background else scheme.onBackground
            Row(Modifier.fillMaxWidth().padding(Space.S3), horizontalArrangement = Arrangement.spacedBy(Space.S3), verticalAlignment = Alignment.Top) {
                Box(Modifier.size(10.dp).offset(y = 6.dp).clip(CircleShape).background(if (note.read) Color.Transparent else scheme.primary))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(note.title, color = ink, fontWeight = if (note.read) FontWeight.Medium else FontWeight.SemiBold, style = MaterialTheme.typography.bodyLarge)
                    if (note.body.isNotEmpty()) Text(note.body, color = ink.copy(alpha = 0.8f), style = MaterialTheme.typography.bodyMedium)
                    Text(ago(note.at), color = ink.copy(alpha = 0.65f), style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        WebButton("Clear", clear, kind = WebButtonKind.Ghost, icon = WebIcons.Close, square = true, spoken = "Clear ${note.title}")
    }
}

private fun ago(unix: Long): String {
    val s = System.currentTimeMillis() / 1000 - unix
    return when {
        s < 45 -> "just now"
        s < 3600 -> "${maxOf(1, s / 60)} min ago"
        s < 86400 -> "${s / 3600} hr ago"
        else -> "${s / 86400} days ago"
    }
}

// What this profile is told about, and whether the phone's own notifications show new ones while the app is open.
@Composable
private fun NoteChoicesPanel(nav: Nav) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val api = nav.app.api
    var choices by remember { mutableStateOf<List<NoteChoice>>(emptyList()) }
    var system by remember { mutableStateOf(SystemNotes.on(context)) }
    LaunchedEffect(Unit) { runCatching { api.noteChoices() }.onSuccess { choices = it } }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        SystemNotes.set(context, granted)
        system = granted
    }
    Column(verticalArrangement = Arrangement.spacedBy(Space.S2), modifier = Modifier.padding(top = Space.S4)) {
        Heading("What you're told about")
        choices.forEach { c ->
            val (name, about) = NoteKinds.names[c.kind] ?: (c.kind to "")
            ChoiceRow(name, about, c.on) { on ->
                choices = choices.map { if (it.kind == c.kind) it.copy(on = on) else it }
                scope.launch { runCatching { api.setNoteChoices(listOf(c.copy(on = on))) }.onSuccess { choices = it } }
            }
        }
        ChoiceRow("On this phone", "Also show new ones in the phone's notifications while the app is open.", system) { on ->
            if (on && Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                ask.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                SystemNotes.set(context, on)
                system = on
            }
        }
    }
}

@Composable
private fun ChoiceRow(name: String, about: String, on: Boolean, change: (Boolean) -> Unit) {
    val scheme = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().semantics(mergeDescendants = true) { contentDescription = name }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S3)) {
        Column(Modifier.weight(1f)) {
            Text(name, color = scheme.onBackground, style = MaterialTheme.typography.bodyLarge)
            if (about.isNotEmpty()) Text(about, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
        Switch(on, change)
    }
}

// The phone's own notifications, while the app is open.
object SystemNotes {
    fun on(context: Context): Boolean = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(SYSTEM_KEY, false) && allowed(context)

    fun set(context: Context, on: Boolean) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(SYSTEM_KEY, on).apply()

    private fun allowed(context: Context) = Build.VERSION.SDK_INT < 33 ||
        ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    fun post(context: Context, fresh: List<Note>) {
        if (fresh.isEmpty() || !allowed(context)) return
        if (Build.VERSION.SDK_INT >= 26) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (manager.getNotificationChannel(CHANNEL) == null) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "Notifications from your server", NotificationManager.IMPORTANCE_DEFAULT))
            }
        }
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val shown = NotificationManagerCompat.from(context)
        fresh.forEach { note ->
            val n = NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_popup_reminder)
                .setContentTitle(note.title)
                .apply { if (note.body.isNotEmpty()) setContentText(note.body) }
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
            try { shown.notify(("note" + note.id).hashCode(), n) } catch (_: SecurityException) { /* permission taken back */ }
        }
    }
}
