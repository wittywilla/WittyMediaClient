package com.wittywilla.wittymediaclient.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.text.format.DateUtils
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.graphics.toColorInt
import androidx.core.net.toUri
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.DeviceSession
import com.wittywilla.wittymediaclient.net.PairInfo
import com.wittywilla.wittymediaclient.net.PairInvite
import com.wittywilla.wittymediaclient.net.Profile
import com.wittywilla.wittymediaclient.net.ProfileUpdate
import com.wittywilla.wittymediaclient.net.TwoFactorSetup
import com.wittywilla.wittymediaclient.net.TwoFactorStatus
import com.wittywilla.wittymediaclient.net.User
import androidx.compose.foundation.shape.RoundedCornerShape
import com.wittywilla.wittymediaclient.net.cleanName
import com.wittywilla.wittymediaclient.net.ThemeTranslator
import com.wittywilla.wittymediaclient.net.ThemeList
import com.wittywilla.wittymediaclient.net.ThemeColour
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// docs/APP-DESIGN.md, "You and settings": the person, their account, this device's choices and, for an
// administrator, the server. What belongs to the person is native here; what the owner manages opens
// the server's own page, or on a TV a QR card for it. The rows themselves are in YouRules.kt.

private val ICONS: Map<String, () -> ImageVector> = mapOf(
    "badge" to { Symbols.Badge }, "key" to { Symbols.Key }, "shield_lock" to { Symbols.ShieldLock },
    "devices" to { Symbols.Devices }, "tv" to { Symbols.Tv }, "family_restroom" to { Symbols.Family },
    "auto_awesome" to { Symbols.Sparkles }, "library_books" to { Symbols.Collections }, "link" to { Symbols.Address },
    "monitoring" to { Symbols.Activity }, "sports_esports" to { Symbols.Games }, "gamepad" to { Symbols.Gamepad },
    "palette" to { Symbols.Palette }, "video_library" to { Symbols.Libraries }, "image_search" to { Symbols.ImageSearch },
    "auto_fix_high" to { Symbols.FixMatches }, "smart_display" to { Symbols.Playback }, "live_tv" to { Symbols.LiveTv },
    "computer" to { Symbols.Computer }, "bolt" to { Symbols.Bolt }, "autorenew" to { Symbols.Autorenew },
    "public" to { Symbols.Globe }, "brush" to { Symbols.Brush }, "dns" to { Symbols.Server }, "article" to { Symbols.Article },
    "stethoscope" to { Symbols.Stethoscope }, "extension" to { Symbols.Extension }, "backup" to { Symbols.Backup },
    "build" to { Symbols.Build }, "restart_alt" to { Symbols.Restart }, "help" to { Symbols.Help }, "info" to { Symbols.Info },
    "gavel" to { Symbols.Gavel }, "menu_book" to { Symbols.Book }, "receipt_long" to { Symbols.Receipt },
)

private fun youIcon(name: String): ImageVector = ICONS[name]?.invoke() ?: Symbols.Info

@Composable
private fun tint(hex: String?): Color = when (hex) {
    null -> Color.Unspecified
    "danger" -> MaterialTheme.colorScheme.error
    else -> Color(hex.toColorInt())
}

// The name of what's chosen on Theme: the server's own theme, Automatic, or a theme's name.
private fun themeName(nav: Nav, themes: ThemeFile, choice: String, s: Map<String, String>): String {
    fun named(id: String) = nav.themeList?.themes?.firstOrNull { it.id == id }?.shownName ?: themes.themes.firstOrNull { it.id == id }?.name
    return when (choice) {
        "" -> named(nav.themeId) ?: s["themeServer"].orEmpty()
        AUTO_THEME -> s["themeAutomatic"].orEmpty()
        ThemeTranslator.CUSTOM_THEME -> s["themeMadeByYou"].orEmpty()
        else -> named(choice) ?: choice
    }
}

// The You tab.
@Composable
fun YouScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val context = LocalContext.current
    val api = nav.app.api
    val themes = remember { Assets.themes(context) }
    var twoStep by remember { mutableStateOf(nav.remembered<TwoFactorStatus>("you-2fa")) }
    var deviceCount by remember { mutableStateOf(nav.remembered<Int>("you-devices")) }
    var hasGames by remember { mutableStateOf(nav.remembered<Boolean>("you-games") ?: false) }
    var version by remember { mutableStateOf(nav.remembered<String>("you-version").orEmpty()) }
    val appVersion = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty() }
    LaunchedEffect(Unit) {
        // Shown at once from last time, asked again underneath.
        runCatching { api.status() }.getOrNull()?.let { status ->
            status.user?.let { nav.me = it }
            version = status.version
            nav.remember("you-version", status.version)
        }
        runCatching { api.twoFactor() }.getOrNull()?.let { twoStep = it; nav.remember("you-2fa", it) }
        runCatching { api.sessions().size }.getOrNull()?.let { deviceCount = it; nav.remember("you-devices", it) }
        runCatching { api.libraries().any { it.type == "games" } }.getOrNull()?.let { hasGames = it; nav.remember("you-games", it) }
    }
    val me = nav.me
    val admin = me?.isAdmin == true
    val who = YouWho(
        admin = admin,
        adult = admin || (me?.kind ?: "adult") == "adult",
        hasGames = hasGames,
        twoStepAvailable = twoStep?.available == true,
        onTv = metrics.tv,
    )
    fun open(row: YouRow) {
        val title = s[row.key].orEmpty()
        nav.push(
            when (val opens = row.opens) {
                is YouOpens.Native -> when (opens.screen) {
                    YouNative.Licences -> Route.Notices
                    YouNative.Log -> Route.Logs
                    else -> Route.You(opens.screen)
                }
                is YouOpens.Page -> if (nav.app.isTv) Route.OnPhone(title, opens.path) else Route.Page(opens.path, title)
            },
        )
    }
    val danger = MaterialTheme.colorScheme.error
    val groups = youGroups(who).map { group ->
        group.key to group.rows.map { row ->
            GroupRow(
                title = s[row.key].orEmpty(),
                onClick = { open(row) },
                icon = youIcon(row.icon),
                tint = tint(row.tint),
                value = when (row.key) {
                    "rowNames" -> me?.let { avatarName(it.displayName, it.name) }.orEmpty()
                    "rowTwoStep" -> twoStep?.let { s[if (it.on) "on" else "off"] }.orEmpty()
                    "rowDevices" -> deviceCount?.toString().orEmpty()
                    "rowTheme" -> themeName(nav, themes, nav.themeChoice, s)
                    "rowAboutServer" -> version
                    else -> ""
                },
                destructive = row.tint == "danger",
                valueColour = if (row.key == "rowTwoStep" && twoStep?.on == true) LocalExtraColours.current.ok else Color.Unspecified,
                focusKey = row.key,
            )
        }
    }
    val list: @Composable ColumnScope.() -> Unit = {
        groups.forEach { (key, rows) -> GroupedList(s[key].orEmpty(), rows) }
        ThisServer(nav, s, showSignOut = !metrics.tv)
        Text(
            "${s["appName"]} $appVersion", color = LocalExtraColours.current.hint, style = MaterialTheme.typography.caption,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
        )
    }
    if (metrics.tv) {
        // The person on the left third, the groups in a list on the right.
        Row(Modifier.fillMaxSize().padding(start = metrics.gutter)) {
            Box(Modifier.weight(1f).fillMaxHeight(), contentAlignment = Alignment.Center) {
                YouHeader(nav, s, me, admin, showSignOut = true)
            }
            Column(
                Modifier
                    .weight(2f)
                    .fillMaxHeight()
                    .verticalScroll(rememberScrollState())
                    .padding(start = metrics.u(48), end = metrics.gutter, top = metrics.u(24), bottom = metrics.edge),
                verticalArrangement = Arrangement.spacedBy(metrics.u(24)),
                content = list,
            )
        }
        return
    }
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier
                .widthIn(max = YOU_MOST)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .statusBarsPadding()
                .padding(horizontal = metrics.gutter)
                .padding(top = Space.S6, bottom = LocalBottomRoom.current + Space.S4),
            verticalArrangement = Arrangement.spacedBy(metrics.u(24)),
        ) {
            YouHeader(nav, s, me, admin, showSignOut = false, modifier = Modifier.align(Alignment.CenterHorizontally))
            ErrorText(nav.notice)
            list()
        }
    }
}

private val YOU_MOST = 640.dp

// The avatar with the person's names centred under it, their role, and Switch profile.
@Composable
private fun YouHeader(nav: Nav, s: Map<String, String>, me: User?, admin: Boolean, showSignOut: Boolean, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val size = metrics.u(
        when {
            metrics.tv -> 200
            metrics.tablet -> 120
            else -> 88
        },
    )
    val shown = me?.let { avatarName(it.displayName, it.name) }.orEmpty()
    Column(modifier.widthIn(max = metrics.u(if (metrics.tv) 520 else 400)), horizontalAlignment = Alignment.CenterHorizontally) {
        Avatar(shown.ifEmpty { "?" }, size)
        Spacer(Modifier.height(metrics.u(12)))
        Text(shown, color = scheme.onBackground, style = MaterialTheme.typography.title, textAlign = TextAlign.Center, modifier = Modifier.semantics { heading() })
        // The username always shows here: this is the account.
        if (me != null) {
            Text(
                "@${me.name} · ${s[roleKey(admin, me.kind)]}", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary,
                textAlign = TextAlign.Center,
            )
        }
        Spacer(Modifier.height(metrics.u(16)))
        // Ends this sign-in and opens Who's watching.
        WittyButton(s["switchProfile"].orEmpty(), nav::signOut, icon = Symbols.Group, requestFocus = metrics.tv, focusKey = "switch-profile")
        if (showSignOut) {
            Spacer(Modifier.height(metrics.u(16)))
            WittyButton(s["signOut"].orEmpty(), nav::signOut, kind = ButtonKind.Destructive, icon = Symbols.SignOut, focusKey = "sign-out")
        }
    }
}

// This server: its card, Change server, and Sign out.
@Composable
private fun ThisServer(nav: Nav, s: Map<String, String>, showSignOut: Boolean) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val server = nav.server ?: return
    Column(verticalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 16 else 12))) {
        Text(
            s["groupThisServer"].orEmpty().uppercase(), color = scheme.onSurfaceVariant, style = MaterialTheme.typography.caption,
            modifier = Modifier.padding(horizontal = metrics.u(16)),
        )
        Row(
            Modifier.fillMaxWidth().clip(metrics.corner(14)).background(scheme.surfaceVariant).padding(metrics.u(16)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(metrics.u(12)),
        ) {
            ServerMark(metrics.u(40), nav.brandLogo)
            Column(Modifier.weight(1f)) {
                Text(server.name, color = scheme.onSurface, style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.SemiBold), maxLines = 1)
                Text(server.url, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, maxLines = 1)
                if (server.fingerprint.isNotEmpty()) {
                    Text("${s["fingerprintLabel"]}: ${server.fingerprint}", color = LocalExtraColours.current.hint, style = MaterialTheme.typography.caption)
                }
            }
        }
        WittyButton(s["changeServer"].orEmpty(), nav::changeServer, Modifier.fillMaxWidth(), tall = true, focusKey = "change-server")
        if (showSignOut) {
            WittyButton(s["signOut"].orEmpty(), nav::signOut, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, icon = Symbols.SignOut, tall = true, focusKey = "sign-out")
        }
    }
}

// One of You's own screens, by what was chosen.
@Composable
fun YouSettingScreen(nav: Nav, s: Map<String, String>, screen: YouNative) {
    when (screen) {
        YouNative.Names -> NamesScreen(nav, s)
        YouNative.Password -> PasswordScreen(nav, s)
        YouNative.TwoStep -> TwoStepScreen(nav, s)
        YouNative.Devices -> DevicesScreen(nav, s)
        YouNative.SignInTv -> SignInTvScreen(nav, s)
        YouNative.Theme -> ThemeScreen(nav, s)
        YouNative.Licences -> NoticesScreen(nav)
        YouNative.Log -> LogsScreen(nav)
    }
}

// A setting's screen: Back, its title and what it's about, then what to change. A phone has one
// column (at most 640 wide); a TV the words on the left third and the rest on the right.
@Composable
private fun SettingsPage(
    nav: Nav,
    title: String,
    detail: String = "",
    onBack: () -> Unit = nav::pop,
    content: @Composable ColumnScope.() -> Unit,
) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    BackHandler { onBack() }
    val words: @Composable ColumnScope.() -> Unit = {
        Text(title, color = scheme.onBackground, style = MaterialTheme.typography.title, modifier = Modifier.semantics { heading() })
        if (detail.isNotEmpty()) Text(detail, color = scheme.onSurfaceVariant, style = MaterialTheme.typography.body)
    }
    Screen {
        if (metrics.tv) {
            Row(Modifier.fillMaxSize().padding(start = metrics.gutter)) {
                Column(
                    Modifier.weight(1f).fillMaxHeight().padding(vertical = metrics.edge),
                    verticalArrangement = Arrangement.spacedBy(metrics.u(12), Alignment.CenterVertically),
                    content = words,
                )
                Column(
                    Modifier
                        .weight(2f)
                        .fillMaxHeight()
                        .verticalScroll(rememberScrollState())
                        .padding(start = metrics.u(48), end = metrics.gutter, top = metrics.edge, bottom = metrics.edge),
                    verticalArrangement = Arrangement.spacedBy(metrics.u(16)),
                    content = content,
                )
            }
        } else {
            Column(Modifier.fillMaxSize().safeDrawingPadding().imePadding()) {
                BackArrow(onBack, Modifier.padding(Space.S1))
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.TopCenter) {
                    Column(
                        Modifier
                            .widthIn(max = YOU_MOST)
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = metrics.gutter)
                            .padding(bottom = Space.S8),
                        verticalArrangement = Arrangement.spacedBy(Space.S4),
                    ) {
                        words()
                        Spacer(Modifier.height(Space.S1))
                        content()
                    }
                }
            }
        }
    }
}

// Something that worked, in `ok`, with a check.
@Composable
private fun Done(text: String, modifier: Modifier = Modifier) {
    if (text.isEmpty()) return
    val ok = LocalExtraColours.current.ok
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(LocalMetrics.current.u(8))) {
        Icon(Symbols.Check, contentDescription = null, tint = ok, modifier = Modifier.size(LocalMetrics.current.u(20)))
        Text(text, color = ok, style = MaterialTheme.typography.body)
    }
}

private fun words(e: Exception, s: Map<String, String>) = problemWords(e, s["errLost"].orEmpty())

// Names: the profile name, the username, and which of them the server's pages show.
@Composable
private fun NamesScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val me = nav.me ?: run { Screen { Loading() }; return }
    var displayName by rememberSaveable { mutableStateOf(me.displayName) }
    var username by rememberSaveable { mutableStateOf(me.name) }
    var showUsername by rememberSaveable { mutableStateOf(me.showUsername) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf("") }
    var saved by remember { mutableStateOf(false) }
    // A Kids or Guest profile's names are the adults' to change; it may still choose which shows.
    val adult = me.isAdmin || me.kind == "adult"
    fun save() {
        if (busy) return
        if (adult && username.isBlank()) {
            problem = s["errUsernameEmpty"].orEmpty()
            return
        }
        val change = ProfileUpdate(
            displayName = displayName.trim().takeIf { adult && it != me.displayName },
            username = username.trim().takeIf { adult && it != me.name },
            showUsername = showUsername.takeIf { it != me.showUsername },
        )
        busy = true
        problem = ""
        scope.launch {
            try {
                if (change != ProfileUpdate()) nav.me = nav.app.api.updateProfile(me.id, change)
                saved = true
                busy = false
                delay(SAVED_MS)
                saved = false
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = words(e, s)
                busy = false
            }
        }
    }
    SettingsPage(nav, s["rowNames"].orEmpty()) {
        // It follows the profile name as it's typed, so its colour can be seen changing.
        Avatar(avatarName(displayName.trim(), username.trim()).ifEmpty { "?" }, metrics.u(64), if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
        Column(verticalArrangement = Arrangement.spacedBy(metrics.u(6))) {
            WittyField(
                displayName, { displayName = it; saved = false; problem = "" }, s["profileNameLabel"].orEmpty(), icon = Symbols.Badge,
                imeAction = ImeAction.Next, maxLength = 60, enabled = adult,
            )
            Hint(if (displayName.isBlank()) s["profileNameEmptyHint"].orEmpty() else s["profileNameHint"].orEmpty())
        }
        Column(verticalArrangement = Arrangement.spacedBy(metrics.u(6))) {
            WittyField(
                username, { username = it; saved = false; problem = "" }, s["usernameLabel"].orEmpty(), kind = FieldKind.Username,
                icon = Symbols.Person, imeAction = ImeAction.Done, onAction = ::save, maxLength = 40, enabled = adult,
            )
            Hint(if (adult) s["usernameHint"].orEmpty() else s["usernameKidsHint"].orEmpty())
        }
        GroupedList(
            "",
            listOf(
                GroupRow(
                    s["showUsernameLabel"].orEmpty(), onClick = { showUsername = !showUsername; saved = false }, detail = s["showUsernameHint"].orEmpty(),
                    chevron = false, focusKey = "show-username",
                    trailing = { Toggle(showUsername) },
                ),
            ),
        )
        Problem(problem, Modifier.fillMaxWidth())
        WittyButton(s["save"].orEmpty(), ::save, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true, focusKey = "save", requestFocus = metrics.tv)
        if (saved) Done(s["saved"].orEmpty())
    }
}

private const val SAVED_MS = 2000L

@Composable
private fun Hint(text: String) {
    if (text.isEmpty()) return
    Text(
        text, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary,
        modifier = Modifier.padding(horizontal = LocalMetrics.current.u(16)),
    )
}

// A switch that only shows: its row is what's pressed, so a remote reaches it as one thing.
@Composable
private fun Toggle(on: Boolean) {
    val scheme = MaterialTheme.colorScheme
    Switch(
        checked = on, onCheckedChange = null,
        colors = SwitchDefaults.colors(
            checkedThumbColor = scheme.onPrimary, checkedTrackColor = scheme.primary,
            uncheckedThumbColor = scheme.onSurfaceVariant, uncheckedTrackColor = scheme.surfaceVariant, uncheckedBorderColor = scheme.outline,
        ),
    )
}

// Password: the current one, then the new one twice. Every other device is signed out after.
@Composable
private fun PasswordScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    val me = nav.me ?: run { Screen { Loading() }; return }
    var current by remember { mutableStateOf("") }
    var fresh by remember { mutableStateOf("") }
    var again by remember { mutableStateOf("") }
    var currentWrong by remember { mutableStateOf(false) }
    var wrongs by remember { mutableIntStateOf(0) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf(false) }
    val first = remember { FocusRequester() }
    val second = remember { FocusRequester() }
    val third = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (!nav.app.isTv) runCatching { first.requestFocus() } }
    LaunchedEffect(wrongs) { if (wrongs > 0) runCatching { first.requestFocus() } }
    fun change() {
        if (busy || done) return
        problem = when {
            fresh.length < MIN_PASSWORD -> s["errPasswordShort"].orEmpty()
            fresh != again -> s["errPasswordsDiffer"].orEmpty()
            else -> ""
        }
        if (problem.isNotEmpty()) return
        busy = true
        scope.launch {
            try {
                nav.app.api.changePassword(me.id, current, fresh)
                done = true
                current = ""
                fresh = ""
                again = ""
                delay(SAVED_MS)
                nav.pop()
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                if (e.status == 403) {
                    // As on sign-in: cleared, red, and focus back in it.
                    problem = s["errCurrentPassword"].orEmpty()
                    current = ""
                    currentWrong = true
                    wrongs++
                } else {
                    problem = words(e, s)
                }
            } catch (e: Exception) {
                problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }
    SettingsPage(nav, s["rowPassword"].orEmpty(), s["passwordChangeHint"].orEmpty()) {
        WittyField(
            current, { current = it; currentWrong = false; problem = "" }, s["currentPasswordLabel"].orEmpty(), kind = FieldKind.Password,
            icon = Symbols.Password, imeAction = ImeAction.Next, onAction = { runCatching { second.requestFocus() } }, focusRequester = first,
            isError = currentWrong, shake = wrongs,
        )
        WittyField(
            fresh, { fresh = it; problem = "" }, s["newPasswordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
            imeAction = ImeAction.Next, onAction = { runCatching { third.requestFocus() } }, focusRequester = second,
        )
        WittyField(
            again, { again = it; problem = "" }, s["repeatPasswordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
            imeAction = ImeAction.Go, onAction = ::change, focusRequester = third,
        )
        Problem(problem, Modifier.fillMaxWidth())
        if (done) {
            Done(s["passwordChanged"].orEmpty())
        } else {
            WittyButton(s["changePassword"].orEmpty(), ::change, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true, focusKey = "change", requestFocus = nav.app.isTv)
        }
    }
}

private const val MIN_PASSWORD = 8

private enum class TwoStepStage { Status, Confirm, Scan, Saved, TurnOff }

// Two-step sign-in: turning it on one step at a time, or off with the password and a code.
@Composable
private fun TwoStepScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val api = nav.app.api
    var status by remember { mutableStateOf<TwoFactorStatus?>(null) }
    var stage by rememberSaveable { mutableStateOf(TwoStepStage.Status) }
    var password by remember { mutableStateOf("") }
    var setup by remember { mutableStateOf<TwoFactorSetup?>(null) }
    var code by remember { mutableStateOf("") }
    var codes by remember { mutableStateOf(emptyList<String>()) }
    var wrong by remember { mutableIntStateOf(0) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        status = try {
            api.twoFactor()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            problem = words(e, s)
            null
        }
    }
    fun run(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        problem = ""
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }
    fun back() {
        when (stage) {
            TwoStepStage.Confirm, TwoStepStage.TurnOff -> { stage = TwoStepStage.Status; password = ""; code = ""; problem = "" }
            TwoStepStage.Scan -> { stage = TwoStepStage.Status; setup = null; code = ""; problem = "" }
            // The recovery codes are the only way on, so they aren't skipped by accident.
            TwoStepStage.Saved -> Unit
            TwoStepStage.Status -> nav.pop()
        }
    }
    fun confirm(digits: String) {
        run {
            try {
                codes = api.twoFactorConfirm(digits).recovery
                stage = TwoStepStage.Saved
            } catch (e: ApiError) {
                if (e.status == 400) {
                    problem = s["errWrongCode"].orEmpty()
                    wrong++
                    code = ""
                } else {
                    throw e
                }
            }
        }
    }
    val press = { digit: Char ->
        if (!busy && code.length < CODE_LENGTH) {
            code += digit
            problem = ""
            if (code.length == CODE_LENGTH) confirm(code)
        }
    }
    val erase = { if (!busy) code = code.dropLast(1) }
    val title = when (stage) {
        TwoStepStage.Confirm -> s["twoStepConfirmTitle"]
        TwoStepStage.Scan -> s["twoStepScanTitle"]
        TwoStepStage.Saved -> s["twoStepSavedTitle"]
        else -> s["rowTwoStep"]
    }.orEmpty()
    val detail = when (stage) {
        TwoStepStage.Scan -> s["twoStepScanHint"]
        TwoStepStage.Saved -> s["twoStepSavedHint"]
        TwoStepStage.TurnOff -> s["twoStepTurnOffHint"]
        TwoStepStage.Status -> if (status?.on == false) s["twoStepIntro"] else ""
        else -> ""
    }.orEmpty()
    Box(if (stage == TwoStepStage.Scan) Modifier.digitKeys(press, erase) else Modifier) {
        SettingsPage(nav, title, detail, onBack = ::back) {
            val current = status
            when (stage) {
                TwoStepStage.Status -> when {
                    current == null -> if (problem.isEmpty()) Spinner(MaterialTheme.colorScheme.onSurfaceVariant, metrics.u(24))
                    !current.available -> Note(s["twoStepUnavailable"].orEmpty())
                    current.on -> {
                        PanelCard {
                            Done(s["twoStepOnTitle"].orEmpty())
                            Text(
                                s["twoStepCodesLeft"].orEmpty().replace("{n}", current.recoveryLeft.toString()),
                                color = if (current.recoveryLeft < FEW_CODES) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                                style = MaterialTheme.typography.secondary,
                            )
                        }
                        WittyButton(s["twoStepTurnOff"].orEmpty(), { stage = TwoStepStage.TurnOff }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, requestFocus = true)
                    }
                    else -> WittyButton(s["twoStepTurnOn"].orEmpty(), { stage = TwoStepStage.Confirm }, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, requestFocus = true)
                }
                TwoStepStage.Confirm -> {
                    WittyField(
                        password, { password = it; problem = "" }, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                        imeAction = ImeAction.Go, onAction = { run { setup = api.twoFactorSetup(password); password = ""; stage = TwoStepStage.Scan } },
                    )
                    Problem(problem, Modifier.fillMaxWidth())
                    WittyButton(
                        s["continue"].orEmpty(), { run { setup = api.twoFactorSetup(password); password = ""; stage = TwoStepStage.Scan } },
                        Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true,
                    )
                }
                TwoStepStage.Scan -> {
                    val made = setup
                    if (made != null) {
                        QrCard(made.uri, "", if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally), size = 200)
                        if (!metrics.tv) {
                            // An authenticator on this phone can take the secret straight from its address.
                            WittyButton(
                                s["twoStepOpenApp"].orEmpty(),
                                { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, made.uri.toUri())) } },
                                Modifier.fillMaxWidth(), icon = Symbols.OpenInNew, tall = true,
                            )
                        }
                        Text(s["twoStepKeyLabel"].orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                            Text(
                                groupsOfFour(made.secret), color = MaterialTheme.colorScheme.onBackground,
                                style = MaterialTheme.typography.label.copy(fontFamily = FontFamily.Monospace), modifier = Modifier.weight(1f, fill = false),
                            )
                            if (!metrics.tv) WittyButton(s["copyAll"].orEmpty(), { copy(context, made.secret) }, kind = ButtonKind.Quiet, icon = Symbols.Copy)
                        }
                        Text(s["twoStepCodeLabel"].orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
                        CodeEntry(code, busy, wrong, onCode = { typed ->
                            code = typed.filter { it.isDigit() }.take(CODE_LENGTH)
                            problem = ""
                            if (code.length == CODE_LENGTH) confirm(code)
                        })
                        Problem(problem, Modifier.fillMaxWidth())
                        if (metrics.tv) NumberPad(press, erase, Modifier.fillMaxWidth(), firstFocus = true)
                    }
                }
                TwoStepStage.Saved -> {
                    PanelCard {
                        codes.chunked(2).forEach { pair ->
                            Row(Modifier.fillMaxWidth()) {
                                pair.forEach {
                                    Text(it, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label.copy(fontFamily = FontFamily.Monospace), modifier = Modifier.weight(1f))
                                }
                            }
                        }
                    }
                    if (!metrics.tv) WittyButton(s["copyAll"].orEmpty(), { copy(context, codes.joinToString("\n")) }, Modifier.fillMaxWidth(), icon = Symbols.Copy, tall = true)
                    WittyButton(
                        s["twoStepDone"].orEmpty(),
                        {
                            status = status?.copy(on = true, recoveryLeft = codes.size)
                            nav.remember("you-2fa", status ?: TwoFactorStatus(on = true, available = true))
                            codes = emptyList()
                            setup = null
                            stage = TwoStepStage.Status
                        },
                        Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, takeFocus = true,
                    )
                }
                TwoStepStage.TurnOff -> {
                    WittyField(password, { password = it; problem = "" }, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password, imeAction = ImeAction.Next)
                    WittyField(code, { code = it.filter { c -> c.isDigit() }.take(CODE_LENGTH); problem = "" }, s["twoStepCodeLabel"].orEmpty(), icon = Symbols.Code, imeAction = ImeAction.Go)
                    Problem(problem, Modifier.fillMaxWidth())
                    WittyButton(
                        s["twoStepTurnOff"].orEmpty(),
                        {
                            run {
                                api.twoFactorDisable(password, code)
                                password = ""
                                code = ""
                                status = status?.copy(on = false, recoveryLeft = 0)
                                status?.let { nav.remember("you-2fa", it) }
                                stage = TwoStepStage.Status
                            }
                        },
                        Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, busy = busy, tall = true,
                    )
                }
            }
            if (stage == TwoStepStage.Status) Problem(problem, Modifier.fillMaxWidth())
        }
    }
}

private const val FEW_CODES = 3

private fun copy(context: Context, text: String) {
    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("WittyMediaClient", text))
}

// Six code boxes over a field that the phone's number keyboard types into.
@Composable
private fun CodeEntry(code: String, checking: Boolean, wrong: Int, onCode: (String) -> Unit) {
    val metrics = LocalMetrics.current
    val field = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (!metrics.tv) runCatching { field.requestFocus() } }
    Box {
        CodeBoxes(code, checking, wrong)
        if (!metrics.tv) {
            BasicTextField(
                code, { if (!checking) onCode(it) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                modifier = Modifier.matchParentSize().graphicsLayer { alpha = 0f }.focusRequester(field),
            )
        }
    }
}

// Your devices: this one first, each with where it is and when it was last seen.
@Composable
private fun DevicesScreen(nav: Nav, s: Map<String, String>) {
    val scope = rememberCoroutineScope()
    var list by remember { mutableStateOf<List<DeviceSession>?>(null) }
    var problem by remember { mutableStateOf("") }
    var asking by remember { mutableStateOf<DeviceSession?>(null) }
    var askingOthers by remember { mutableStateOf(false) }
    suspend fun load() {
        list = try {
            nav.app.api.sessions().sortedWith(compareByDescending<DeviceSession> { it.current }.thenByDescending { it.lastSeen })
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            problem = words(e, s)
            list
        }
    }
    LaunchedEffect(Unit) { load() }
    fun end(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
                load()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = words(e, s)
            }
        }
    }
    val now = System.currentTimeMillis()
    SettingsPage(nav, s["rowDevices"].orEmpty(), s["devicesHint"].orEmpty()) {
        val devices = list
        if (devices == null) {
            if (problem.isEmpty()) Spinner(MaterialTheme.colorScheme.onSurfaceVariant, LocalMetrics.current.u(24))
        } else {
            GroupedList(
                "",
                devices.mapIndexed { i, d ->
                    val where = s[
                        when (d.where) {
                            "machine" -> "whereMachine"
                            "home" -> "whereHome"
                            "vpn" -> "whereVpn"
                            else -> "whereInternet"
                        },
                    ].orEmpty()
                    val seen = if (now - d.lastSeen * 1000 < ACTIVE_MS) s["activeNow"].orEmpty()
                    else DateUtils.getRelativeTimeSpanString(d.lastSeen * 1000, now, DateUtils.MINUTE_IN_MILLIS).toString()
                    GroupRow(
                        title = d.device.ifEmpty { "?" },
                        detail = listOf(where, seen).filter { it.isNotEmpty() }.joinToString(" · "),
                        icon = when (deviceKind(d.device)) {
                            "tv" -> Symbols.Tv
                            "tablet" -> Symbols.Tablet
                            "phone" -> Symbols.Phone
                            "browser" -> Symbols.Browser
                            else -> Symbols.Computer
                        },
                        tint = Color(0xFF7F46B8),
                        // On a TV the row itself is pressed, then asked; a phone has the button.
                        onClick = if (!d.current && nav.app.isTv) { { asking = d } } else null,
                        chevron = false,
                        focusKey = "device-${d.id}",
                        requestFocus = nav.app.isTv && i == devices.indexOfFirst { !it.current },
                        trailing = {
                            if (d.current) Tag(s["thisDevice"].orEmpty())
                            else if (!nav.app.isTv) WittyButton(s["signOut"].orEmpty(), { asking = d }, kind = ButtonKind.Quiet)
                        },
                    )
                },
            )
            if (devices.any { !it.current }) {
                WittyButton(s["signOutOthers"].orEmpty(), { askingOthers = true }, Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, tall = true, focusKey = "sign-out-others")
            }
        }
        Problem(problem, Modifier.fillMaxWidth())
    }
    asking?.let { d ->
        Confirm(
            s["signOutDeviceConfirm"].orEmpty().replace("{device}", d.device), s["signOut"].orEmpty(), s["cancel"].orEmpty(),
            onYes = { asking = null; end { nav.app.api.endSession(d.id) } }, onNo = { asking = null },
        )
    }
    if (askingOthers) {
        Confirm(
            s["signOutOthersConfirm"].orEmpty(), s["signOutOthers"].orEmpty(), s["cancel"].orEmpty(),
            onYes = { askingOthers = false; end { nav.app.api.endOtherSessions() } }, onNo = { askingOthers = false },
        )
    }
}

private const val ACTIVE_MS = 5 * 60 * 1000L

// Are you sure: the safe answer has focus.
@Composable
private fun Confirm(question: String, yes: String, no: String, onYes: () -> Unit, onNo: () -> Unit) {
    AlertDialog(
        onDismissRequest = onNo,
        containerColor = MaterialTheme.colorScheme.surface,
        text = { Text(question, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.body) },
        confirmButton = { WittyButton(yes, onYes, kind = ButtonKind.Destructive) },
        dismissButton = { WittyButton(no, onNo, requestFocus = true) },
    )
}

// Sign in a TV: the code the TV shows (eight letters), then what's asking, then yes or no. Or a code for
// the TV to type instead.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SignInTvScreen(nav: Nav, s: Map<String, String>) {
    val metrics = LocalMetrics.current
    val scope = rememberCoroutineScope()
    val api = nav.app.api
    val me = nav.me ?: run { Screen { Loading() }; return }
    val adult = me.isAdmin || me.kind == "adult"
    var code by remember { mutableStateOf("") }
    var info by remember { mutableStateOf<PairInfo?>(null) }
    var chosen by remember { mutableStateOf<Long?>(null) }
    var names by remember { mutableStateOf(emptyMap<Long, Profile>()) }
    var invite by remember { mutableStateOf<PairInvite?>(null) }
    var outcome by remember { mutableStateOf("") }
    var good by remember { mutableStateOf(false) }
    var wrong by remember { mutableIntStateOf(0) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    // The pairing answer has usernames only; the profile list has the names people chose.
    LaunchedEffect(Unit) {
        runCatching { api.profiles().profiles }.getOrNull()?.let { list -> names = list.associateBy { it.id } }
    }
    fun run(block: suspend () -> Unit) {
        if (busy) return
        busy = true
        problem = ""
        scope.launch {
            try {
                block()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = words(e, s)
            } finally {
                busy = false
            }
        }
    }
    fun look(typed: String) {
        run {
            try {
                val found = api.pairInfo(typed)
                info = found
                chosen = found.profiles.firstOrNull()?.id ?: me.id
            } catch (e: ApiError) {
                wrong++
                code = ""
                throw e
            }
        }
    }
    fun reset() {
        code = ""
        info = null
        invite = null
        outcome = ""
        problem = ""
    }
    SettingsPage(nav, s["rowSignInTv"].orEmpty(), if (info == null && invite == null && outcome.isEmpty()) s["signInTvHint"].orEmpty() else "") {
        val asking = info
        val made = invite
        when {
            !adult -> Note(s["signInTvAdultOnly"].orEmpty())
            outcome.isNotEmpty() -> {
                if (good) Done(outcome) else Text(outcome, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.body)
                WittyButton(s["signInTvAnother"].orEmpty(), ::reset, Modifier.fillMaxWidth(), tall = true, takeFocus = true)
            }
            made != null -> {
                PanelCard {
                    Text(
                        made.code, color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth(),
                        style = MaterialTheme.typography.display.copy(fontFamily = FontFamily.Monospace, letterSpacing = MaterialTheme.typography.display.fontSize * 0.25f),
                    )
                }
                Text(
                    s["signInTvInviteHint"].orEmpty().replace("{minutes}", (made.expiresInSec / 60).coerceAtLeast(1).toString()),
                    color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary,
                )
                WittyButton(s["signInTvAnother"].orEmpty(), ::reset, Modifier.fillMaxWidth(), tall = true)
            }
            asking != null -> {
                PanelCard {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                        IconTile(Symbols.Tv, Color(0xFFBD2F85))
                        Column {
                            Text(asking.device, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label.copy(fontWeight = FontWeight.SemiBold))
                            val facts = listOf(asking.platform, asking.ip).filter { it.isNotEmpty() }.joinToString(" · ")
                            if (facts.isNotEmpty()) Text(facts, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
                        }
                    }
                }
                Text(s["signInTvAs"].orEmpty(), color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.section)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(metrics.u(24)), verticalArrangement = Arrangement.spacedBy(metrics.u(16))) {
                    asking.profiles.forEach { choice ->
                        val known = names[choice.id] ?: Profile(choice.id, choice.name, "", choice.kind)
                        Box(
                            Modifier.then(
                                if (chosen == choice.id) Modifier.border(2.dp, MaterialTheme.colorScheme.primary, metrics.corner(14)).padding(metrics.u(6)) else Modifier.padding(metrics.u(6)),
                            ),
                        ) {
                            ProfileTile(known, metrics.u(72), { chosen = choice.id }, focusKey = "as-${choice.id}")
                        }
                    }
                }
                Problem(problem, Modifier.fillMaxWidth())
                WittyButton(
                    s["signInTvApprove"].orEmpty(),
                    { run { api.pairApprove(code, chosen ?: me.id); good = true; outcome = s["signInTvDone"].orEmpty() } },
                    Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true, takeFocus = true,
                )
                WittyButton(
                    s["signInTvDeny"].orEmpty(),
                    { run { api.pairDeny(code); good = false; outcome = s["signInTvDenied"].orEmpty() } },
                    if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally), kind = ButtonKind.Quiet,
                )
            }
            else -> {
                TvCodeEntry(code, busy, wrong, if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally)) { typed ->
                    code = tvCodeTyped(typed)
                    problem = ""
                    if (code.length == TV_CODE_LENGTH) look(code)
                }
                Problem(problem, Modifier.fillMaxWidth())
                WittyButton(
                    s["signInTvInvite"].orEmpty(), { run { invite = api.pairInvite(me.id) } },
                    if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally), kind = ButtonKind.Quiet,
                )
            }
        }
    }
}

// A TV's code: eight boxes, four, a dash, four, over a capitals keyboard. The server's own letters only.
@Composable
private fun TvCodeEntry(code: String, checking: Boolean, wrong: Int, modifier: Modifier = Modifier, onCode: (String) -> Unit) {
    val metrics = LocalMetrics.current
    val scheme = MaterialTheme.colorScheme
    val field = remember { FocusRequester() }
    val shake = rememberShake(wrong)
    // What the keyboard typed, as it typed it: filtering it in place upsets a keyboard that's still
    // composing a word, and letters go missing. The code is made from it.
    var typed by remember { mutableStateOf(code) }
    LaunchedEffect(code) { if (code.isEmpty()) typed = "" }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
    Box(modifier.graphicsLayer { translationX = shake.value * density }) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(6))) {
            for (place in 0 until TV_CODE_LENGTH) {
                if (place == TV_CODE_LENGTH / 2) Text("–", color = scheme.onSurfaceVariant, style = MaterialTheme.typography.title)
                val next = place == code.length && !checking
                Box(
                    Modifier
                        .width(metrics.u(34))
                        .height(metrics.u(48))
                        .clip(metrics.corner(10))
                        .background(scheme.surfaceVariant)
                        .border(metrics.u(2), if (checking || next) scheme.primary else Color.Transparent, metrics.corner(10)),
                    contentAlignment = Alignment.Center,
                ) {
                    code.getOrNull(place)?.let {
                        Text(it.toString(), color = scheme.onSurface, style = MaterialTheme.typography.headline.copy(fontFamily = FontFamily.Monospace))
                    }
                }
            }
        }
        BasicTextField(
            typed,
            {
                if (!checking) {
                    typed = it.take(TYPED_MOST)
                    onCode(typed)
                }
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Ascii, capitalization = androidx.compose.ui.text.input.KeyboardCapitalization.Characters, autoCorrectEnabled = false, imeAction = ImeAction.Done),
            modifier = Modifier.matchParentSize().graphicsLayer { alpha = 0f }.focusRequester(field),
        )
    }
}

private const val TYPED_MOST = 16

// Theme on this device (docs/APP-DESIGN.md, Themes, Choosing): Automatic, the server's choice, Made by you when the
// account has its own look, then every theme the server has, each with a swatch from its preview. Applied at once.
@Composable
private fun ThemeScreen(nav: Nav, s: Map<String, String>) {
    val context = LocalContext.current
    val bundled = remember { Assets.themes(context) }
    val choice = nav.themeChoice
    // The server's list, or the built-ins until it comes.
    val offered: List<ThemeList.ThemeSummary> = nav.themeList?.themes ?: bundled.themes.map {
        ThemeList.ThemeSummary(it.id, it.name, it.scheme, preview = ThemeList.Preview(it.colours.background, it.colours.card, it.colours.text, it.colours.accent))
    }
    val check: @Composable (String) -> Unit = { id ->
        Icon(
            Symbols.Check, contentDescription = null, tint = LocalExtraColours.current.accentText,
            modifier = Modifier.size(LocalMetrics.current.u(20)).graphicsLayer { alpha = if (choice == id) 1f else 0f },
        )
    }
    SettingsPage(nav, s["rowTheme"].orEmpty(), s["themeHint"].orEmpty()) {
        val firsts = buildList {
            add(
                GroupRow(
                    s["themeAutomatic"].orEmpty(), onClick = { nav.chooseTheme(AUTO_THEME) }, icon = Symbols.Contrast, tint = Color(0xFF0E7C6F),
                    detail = s["themeAutomaticHint"].orEmpty(), chevron = false, selected = choice == AUTO_THEME, focusKey = "theme-auto",
                    requestFocus = choice == AUTO_THEME, trailing = { check(AUTO_THEME) },
                ),
            )
            add(
                GroupRow(
                    s["themeServer"].orEmpty(), onClick = { nav.chooseTheme("") }, icon = Symbols.Server, tint = Color(0xFF5D6474),
                    detail = themeName(nav, bundled, "", s), chevron = false, selected = choice.isEmpty(),
                    focusKey = "theme-server", trailing = { check("") }, requestFocus = choice.isEmpty(),
                ),
            )
            val mine = nav.customTheme
            if (mine != null) {
                val made = remember(mine) { ThemeTranslator.translateMade(mine) }
                add(
                    GroupRow(
                        s["themeMadeByYou"].orEmpty(), onClick = { nav.chooseTheme(ThemeTranslator.CUSTOM_THEME) }, chevron = false,
                        detail = cleanName(mine.name), selected = choice == ThemeTranslator.CUSTOM_THEME, focusKey = "theme-custom",
                        requestFocus = choice == ThemeTranslator.CUSTOM_THEME,
                        leading = { Swatch(made.background, made.card, made.accent) }, trailing = { check(ThemeTranslator.CUSTOM_THEME) },
                    ),
                )
            }
        }
        GroupedList("", firsts)
        GroupedList(
            "",
            offered.map { theme ->
                val p = theme.preview
                GroupRow(
                    theme.shownName, onClick = { nav.chooseTheme(theme.id) }, chevron = false, selected = choice == theme.id,
                    detail = if (theme.webOnly) s["themeLooksPlainer"].orEmpty() else "", focusKey = "theme-${theme.id}",
                    requestFocus = choice == theme.id,
                    leading = {
                        Swatch(
                            ThemeColour.parse(p?.bg) ?: ThemeColour.BLACK, ThemeColour.parse(p?.surface) ?: ThemeColour.BLACK,
                            ThemeColour.parse(p?.accent) ?: ThemeColour.WHITE,
                        )
                    },
                    trailing = { check(theme.id) },
                )
            },
        )
        if (offered.any { it.webOnly }) Hint(s["themeWebOnly"].orEmpty())
    }
}

// A theme at a glance: its page, a card stripe and an accent dot.
@Composable
private fun Swatch(page: ThemeColour, card: ThemeColour, accent: ThemeColour) {
    val metrics = LocalMetrics.current
    val size = metrics.u(if (metrics.tv) 32 else 28)
    Box(
        Modifier
            .size(size)
            .clip(RoundedCornerShape(metrics.u(7)))
            .background(Color(page.argb))
            .border(1.dp, MaterialTheme.colorScheme.outline, RoundedCornerShape(metrics.u(7))),
    ) {
        Box(Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(size * 0.36f).background(Color(card.argb)))
        Box(Modifier.align(Alignment.TopEnd).padding(size * 0.18f).size(size * 0.32f).clip(CircleShape).background(Color(accent.argb)))
    }
}
