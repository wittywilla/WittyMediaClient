package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.net.Address
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.FoundServer
import com.wittywilla.wittymediaclient.net.Probe
import com.wittywilla.wittymediaclient.net.Profile
import com.wittywilla.wittymediaclient.net.Profiles
import com.wittywilla.wittymediaclient.net.ServerFinder
import com.wittywilla.wittymediaclient.net.probeServer
import com.wittywilla.wittymediaclient.net.problemWords
import kotlinx.coroutines.CancellationException
import java.io.IOException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private fun reasonText(s: Map<String, String>, reason: String) = when (reason) {
    "empty" -> s["errEmpty"]
    "scheme" -> s["errScheme"]
    "credentials" -> s["errCredentials"]
    "public-http" -> s["errPublicHttp"]
    "unreachable" -> s["errUnreachable"]
    "not-server" -> s["errNotServer"]
    "not-set-up" -> s["errNotSetUp"]
    "server-old" -> s["errServerOld"]
    "app-old" -> s["errAppOld"]
    "certificate" -> s["errCertificate"]
    else -> s["errInvalid"]
}.orEmpty()

// A text box a remote can leave: down moves on instead of being swallowed.
@Composable
private fun Field(
    value: String,
    onChange: (String) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    password: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    onDone: () -> Unit,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
        keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else keyboard, imeAction = ImeAction.Go, autoCorrectEnabled = false),
        keyboardActions = KeyboardActions(onGo = { onDone() }),
        modifier = modifier.fillMaxWidth().tvLeavable(),
    )
}

// A text box otherwise keeps up and down for itself, and a remote can't get out of it.
@Composable
fun Modifier.tvLeavable(): Modifier {
    val focus = LocalFocusManager.current
    return onPreviewKeyEvent {
        if (it.type == KeyEventType.KeyDown && it.key.nativeKeyCode == KeyEvent.KEYCODE_DPAD_DOWN) {
            focus.moveFocus(FocusDirection.Down)
        } else if (it.type == KeyEventType.KeyDown && it.key.nativeKeyCode == KeyEvent.KEYCODE_DPAD_UP) {
            focus.moveFocus(FocusDirection.Up)
        } else {
            false
        }
    }
}

@Composable
private fun Centred(content: @Composable () -> Unit) {
    Screen {
        Column(
            Modifier.fillMaxWidth().safeDrawingPadding().imePadding().verticalScroll(rememberScrollState()).padding(Space.S8),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Column(Modifier.widthIn(max = 560.dp).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) { content() }
        }
    }
}

// What to read and what to press. Side by side on a TV, where a tall screen would scroll its
// beginning out of sight. One above the other everywhere else.
@Composable
private fun SideBySide(modifier: Modifier = Modifier, words: @Composable () -> Unit, actions: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    if (metrics.tv) {
        Screen {
            Row(
                modifier.fillMaxSize().padding(horizontal = metrics.gutter, vertical = metrics.edge),
                horizontalArrangement = Arrangement.spacedBy(Space.S12),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) { words() }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(12.dp)) { actions() }
            }
        }
    } else {
        Centred {
            Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                words()
                actions()
            }
        }
    }
}

// A server in a list: its name, and the address it's at.
@Composable
private fun ServerRow(name: String, url: String, requestFocus: Boolean, onClick: () -> Unit) {
    FocusBox(onClick, Modifier.fillMaxWidth(), label = "$name, $url", requestFocus = requestFocus, filled = MaterialTheme.colorScheme.surfaceVariant) {
        Column(Modifier.padding(horizontal = 18.dp, vertical = 11.dp)) {
            Text(name, color = MaterialTheme.colorScheme.onSurface)
            Secondary(url)
        }
    }
}

private val ARROWS = setOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)
private const val NONE_AFTER_MS = 6000L

@Composable
fun ConnectScreen(nav: Nav, s: Map<String, String>, message: String) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val recent = remember { nav.app.store.recent }
    val appVersion = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty() }
    var address by rememberSaveable { mutableStateOf("") }
    var error by rememberSaveable(message) { mutableStateOf(message) }
    var busy by remember { mutableStateOf(false) }
    var showForm by rememberSaveable { mutableStateOf(false) }
    var found by remember { mutableStateOf(emptyList<FoundServer>()) }
    var searchedLong by remember { mutableStateOf(false) }
    var moved by remember { mutableStateOf(false) }
    val fieldFocus = remember { FocusRequester() }

    // Only looks while this screen is open.
    DisposableEffect(Unit) {
        val finder = ServerFinder(context) { found = it }
        finder.start()
        onDispose { finder.stop() }
    }
    LaunchedEffect(Unit) {
        delay(NONE_AFTER_MS)
        searchedLong = true
    }
    BackHandler(enabled = showForm) { showForm = false; error = "" }

    fun connect(url: String) {
        if (busy) return
        busy = true
        error = ""
        scope.launch {
            val problem = when (val r = probeServer(url, appVersion)) {
                is Probe.Found -> nav.arrive(r.url, r.status)
                is Probe.Failed -> reasonText(s, r.reason)
            }
            if (problem != null) {
                error = problem
                address = url
                showForm = true
            }
            busy = false
        }
    }

    fun submit() {
        when (val r = Address.normalize(address)) {
            is Address.Result.Ok -> connect(r.url)
            is Address.Result.Bad -> error = reasonText(s, r.reason)
        }
    }

    val words: @Composable () -> Unit = {
        Heading(s["findTitle"].orEmpty())
        Secondary(s["legalConnect"].orEmpty())
        ErrorText(error)
        if (busy) Secondary(s["connecting"].orEmpty())
    }
    // The first server found takes focus, until the person has moved themselves.
    val servers: @Composable () -> Unit = {
        Secondary(s["foundServers"].orEmpty())
        if (found.isEmpty()) Secondary(if (searchedLong) s["findNone"].orEmpty() else s["findSearching"].orEmpty())
        found.forEachIndexed { i, server ->
            key(server.id) { ServerRow(server.name, server.url, i == 0 && !moved) { connect(server.url) } }
        }
        val others = recent.filter { r -> found.none { it.url == r.url || it.id == r.serverId } }
        if (others.isNotEmpty()) Secondary(s["recentServers"].orEmpty())
        others.forEachIndexed { i, server ->
            key(server.url) { ServerRow(server.name, server.url, found.isEmpty() && i == 0 && !moved) { connect(server.url) } }
        }
        ActionButton(s["enterAddress"].orEmpty(), { showForm = true; error = "" }, Modifier.fillMaxWidth(), requestFocus = found.isEmpty() && others.isEmpty())
    }
    val notesMoved = Modifier.onPreviewKeyEvent {
        if (it.type == KeyEventType.KeyDown && it.key.nativeKeyCode in ARROWS) moved = true
        false
    }

    when {
        showForm -> Centred {
            LaunchedEffect(Unit) { runCatching { fieldFocus.requestFocus() } }
            Heading(s["addressTitle"].orEmpty())
            Secondary(s["addressHint"].orEmpty())
            Field(address, { address = it; error = "" }, s["addressLabel"].orEmpty(), Modifier.focusRequester(fieldFocus), keyboard = KeyboardType.Uri, onDone = ::submit)
            ErrorText(error)
            ActionButton(if (busy) s["connecting"].orEmpty() else s["connect"].orEmpty(), ::submit, Modifier.fillMaxWidth(), primary = true, enabled = !busy)
            ActionButton(s["back"].orEmpty(), { showForm = false; error = "" }, Modifier.fillMaxWidth())
            Secondary(s["legalConnect"].orEmpty())
        }
        // Side by side, so that a long list of servers doesn't scroll the words out of sight.
        LocalMetrics.current.tv -> SideBySide(words = words, actions = {
            Column(notesMoved.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) { servers() }
        })
        else -> Centred {
            Column(notesMoved, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                words()
                servers()
            }
        }
    }
}

@Composable
private fun PadKey(key: Int, keys: List<FocusRequester>, label: String, small: Boolean, onClick: () -> Unit, modifier: Modifier) {
    FocusBox(
        onClick,
        modifier
            .focusRequester(keys[key])
            .focusProperties {
                padMove(key, PadMove.Up)?.let { up = keys[it] }
                padMove(key, PadMove.Down)?.let { down = keys[it] }
                padMove(key, PadMove.Left)?.let { left = keys[it] }
                padMove(key, PadMove.Right)?.let { right = keys[it] }
            },
        requestFocus = key == 0,
        filled = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(Modifier.fillMaxWidth().height(LocalMetrics.current.minTarget + Space.S2), contentAlignment = Alignment.Center) {
            Text(label, color = MaterialTheme.colorScheme.onSurface, style = if (small) MaterialTheme.typography.labelLarge else MaterialTheme.typography.headlineSmall)
        }
    }
}

// Works with only a remote: arrows and OK. Touch and number keys work as well.
@Composable
private fun NumberPad(deleteLabel: String, onDigit: (Char) -> Unit, onDelete: () -> Unit) {
    val keys = remember { List(PAD_KEYS.size) { FocusRequester() } }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (row in 0..2) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                for (column in 0..2) {
                    val key = row * 3 + column
                    PadKey(key, keys, PAD_KEYS[key], false, { onDigit(PAD_KEYS[key][0]) }, Modifier.weight(1f))
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PadKey(PAD_DELETE, keys, deleteLabel, true, onDelete, Modifier.weight(1f))
            PadKey(PAD_ZERO, keys, PAD_KEYS[PAD_ZERO], false, { onDigit('0') }, Modifier.weight(2f))
        }
    }
}

// A new server is opened with a six-digit code from someone already signed in. See
// docs/CLIENT-API.md, "The code is typed on the device".
@Composable
fun CodeScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
    var entry by remember { mutableStateOf(CodeEntry()) }
    var problem by remember { mutableStateOf("") }

    fun press(digit: Char) {
        val next = entry.typed(digit)
        if (next == entry) return
        problem = ""
        entry = next
        if (!next.complete) return
        entry = next.copy(busy = true)
        scope.launch {
            val failed = nav.redeem(server, next.digits)
            if (failed != null) {
                entry = CodeEntry()
                problem = failed
            }
        }
    }

    SideBySide(
        Modifier.onPreviewKeyEvent {
            if (it.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
            when (val code = it.key.nativeKeyCode) {
                in KeyEvent.KEYCODE_0..KeyEvent.KEYCODE_9 -> { press('0' + (code - KeyEvent.KEYCODE_0)); true }
                in KeyEvent.KEYCODE_NUMPAD_0..KeyEvent.KEYCODE_NUMPAD_9 -> { press('0' + (code - KeyEvent.KEYCODE_NUMPAD_0)); true }
                KeyEvent.KEYCODE_DEL -> { entry = entry.erased(); true }
                else -> false
            }
        },
        words = {
            Heading(s["codeTitle"].orEmpty())
            // Several servers can look alike in the list: this says which one the code goes to.
            Secondary("${server.name} · ${server.url}")
            Secondary(s["codeHint"].orEmpty())
            Text(
                entry.shown,
                color = MaterialTheme.colorScheme.onBackground,
                style = MaterialTheme.typography.displaySmall,
                modifier = Modifier.semantics {
                    contentDescription = "${s["codeLabel"]}: ${entry.digits.length} ${s["codeEntered"]}"
                },
            )
            // Room is kept for the message, or the keys would move under a finger as it comes and goes.
            Box(Modifier.heightIn(min = MaterialTheme.typography.bodyLarge.lineHeight.value.dp * 2)) {
                if (entry.busy) Secondary(s["connecting"].orEmpty()) else ErrorText(problem)
            }
            Secondary("${s["fingerprintLabel"]}: ${server.fingerprint}")
        },
        actions = {
            NumberPad(s["codeDelete"].orEmpty(), ::press) { entry = entry.erased() }
            ActionButton(s["usePassword"].orEmpty(), { nav.signInTo(server, SignInWay.Password) }, Modifier.fillMaxWidth())
            ActionButton(s["showCodeInstead"].orEmpty(), { nav.signInTo(server, SignInWay.ShownCode) }, Modifier.fillMaxWidth())
        },
    )
}

// Another machine is answering for a server we know. Only the person can decide,
// so the safe choice has focus, and nothing has been sent to it.
@Composable
fun MismatchScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    Centred {
        Heading(s["identityTitle"].orEmpty())
        Secondary(s["identityHint"].orEmpty())
        Secondary("${server.url} · ${s["fingerprintLabel"]}: ${server.fingerprint}")
        ErrorText(problem)
        ActionButton(s["back"].orEmpty(), nav::pop, Modifier.fillMaxWidth(), primary = true, requestFocus = true)
        ActionButton(
            s["identityTrust"].orEmpty(),
            {
                busy = true
                scope.launch {
                    problem = nav.trust(server).orEmpty()
                    busy = false
                }
            },
            Modifier.fillMaxWidth(),
            enabled = !busy,
        )
    }
}

// Only a server that has proved its identity can be sent a code.
@Composable
private fun TypedCodeButton(nav: Nav, s: Map<String, String>) {
    val server = nav.server
    if (server != null && server.publicKey.isNotEmpty()) {
        ActionButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, Modifier.fillMaxWidth())
    }
}

// The TV shows a code; someone already signed in on a phone or computer approves
// it, so nobody has to type a password with a remote. See docs/CLIENT-API.md.
@Composable
private fun PairPanel(nav: Nav, s: Map<String, String>, onUsePassword: () -> Unit) {
    var round by remember { mutableStateOf(0) }
    var code by remember { mutableStateOf("") }
    var approveAt by remember { mutableStateOf("") }
    var scan by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    var waiting by remember { mutableStateOf(false) }

    LaunchedEffect(round) {
        code = ""
        problem = ""
        waiting = false
        try {
            val start = nav.app.api.pairStart(nav.app.deviceName, nav.app.platformName)
            code = start.code
            approveAt = nav.app.api.mediaUrl(start.approvePath)
            scan = start.approveUrl.ifEmpty { start.approvePath }.let { nav.app.api.mediaUrl(it) }
            var wait = start.intervalSec.coerceAtLeast(1)
            while (true) {
                delay(wait * 1000L)
                // A network that blinks is no reason to give up on a code that's still good.
                val poll = try {
                    nav.app.api.pairPoll(start.deviceSecret).also { waiting = false }
                } catch (_: IOException) {
                    waiting = true
                    continue
                }
                when (poll.status) {
                    "approved" -> {
                        if (poll.token.isEmpty()) {
                            problem = s["errInvalid"].orEmpty()
                            code = ""
                        } else {
                            nav.signedIn(poll.token)
                        }
                        return@LaunchedEffect
                    }
                    "denied" -> { problem = s["pairDenied"].orEmpty(); code = ""; return@LaunchedEffect }
                    "expired" -> { problem = s["pairExpired"].orEmpty(); code = ""; return@LaunchedEffect }
                    "slow-down" -> wait = (poll.intervalSec.coerceAtLeast(wait)) + 1
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            code = ""
            problem = problemWords(e, s["errLost"].orEmpty())
        }
    }

    SideBySide(
        words = {
            Heading(s["pairTitle"].orEmpty())
            if (code.isNotEmpty()) {
                Secondary(s["pairHint"].orEmpty())
                Text(approveAt, color = MaterialTheme.colorScheme.onBackground)
                Text(code, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.displayMedium, modifier = Modifier.semantics { contentDescription = code.toList().joinToString(" ") })
                Secondary(if (waiting) s["errLost"].orEmpty() else s["pairWaiting"].orEmpty())
            }
            ErrorText(problem)
        },
        actions = {
            if (code.isNotEmpty() && scan.isNotEmpty()) {
                Secondary(s["pairScan"].orEmpty())
                QrCode(scan, Modifier.semantics { contentDescription = s["pairScan"].orEmpty() })
            }
            if (code.isEmpty() && problem.isNotEmpty()) ActionButton(s["pairNew"].orEmpty(), { round++ }, Modifier.fillMaxWidth(), primary = true, requestFocus = true)
            TypedCodeButton(nav, s)
            ActionButton(s["usePassword"].orEmpty(), onUsePassword, Modifier.fillMaxWidth(), requestFocus = code.isNotEmpty())
            ActionButton(s["changeServer"].orEmpty(), nav::changeServer, Modifier.fillMaxWidth())
        },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun SignInScreen(nav: Nav, s: Map<String, String>, way: SignInWay) {
    val scope = rememberCoroutineScope()
    // On a TV the code comes first. Everywhere else a keyboard is at hand.
    var useCode by rememberSaveable { mutableStateOf(way == SignInWay.ShownCode || (way == SignInWay.Usual && nav.app.isTv)) }
    var profiles by remember { mutableStateOf<Profiles?>(null) }
    var chosen by remember { mutableStateOf<Profile?>(null) }
    var useForm by rememberSaveable { mutableStateOf(false) }
    var name by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    val passwordFocus = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        profiles = runCatching { nav.app.api.profiles() }.getOrDefault(Profiles())
    }

    fun login(who: String, secret: String) {
        if (busy) return
        busy = true
        error = ""
        scope.launch {
            try {
                val refused = nav.server?.let { nav.clearToSend(it) }
                if (refused != null) {
                    error = refused
                } else {
                    val result = nav.app.api.login(who, secret, nav.app.deviceName)
                    if (result.token.isEmpty()) error = s["errInvalid"].orEmpty() else nav.signedIn(result.token)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                error = problemWords(e, s["errLost"].orEmpty())
            } finally {
                busy = false
            }
        }
    }

    if (useCode) {
        PairPanel(nav, s) { useCode = false }
        return
    }
    val list = profiles
    Centred {
        when {
            list == null -> Loading()
            chosen != null -> {
                val who = chosen!!
                LaunchedEffect(who.id) { runCatching { passwordFocus.requestFocus() } }
                Heading(who.name)
                Field(password, { password = it }, "Password", Modifier.focusRequester(passwordFocus), password = true, onDone = { login(who.name, password) })
                ErrorText(error)
                ActionButton("Sign in", { login(who.name, password) }, Modifier.fillMaxWidth(), primary = true, enabled = !busy)
                ActionButton(s["back"].orEmpty(), { chosen = null; password = ""; error = "" }, Modifier.fillMaxWidth())
            }
            list.style == "profiles" && !useForm && list.profiles.isNotEmpty() -> {
                Heading("Who's watching?")
                ErrorText(error)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    list.profiles.forEachIndexed { i, p ->
                        ActionButton(p.name, { if (p.hasPassword) chosen = p else login(p.name, "") }, requestFocus = i == 0)
                    }
                }
                ActionButton("Sign in with another account", { useForm = true }, Modifier.fillMaxWidth())
                TypedCodeButton(nav, s)
                ActionButton(s["useCode"].orEmpty(), { useCode = true }, Modifier.fillMaxWidth())
                ActionButton(s["changeServer"].orEmpty(), nav::changeServer, Modifier.fillMaxWidth())
            }
            else -> {
                Heading("Sign in")
                Field(name, { name = it }, "Name", onDone = { runCatching { passwordFocus.requestFocus() } })
                Field(password, { password = it }, "Password", Modifier.focusRequester(passwordFocus), password = true, onDone = { login(name, password) })
                ErrorText(error)
                ActionButton("Sign in", { login(name, password) }, Modifier.fillMaxWidth(), primary = true, enabled = !busy)
                if (list.profiles.isNotEmpty()) ActionButton(s["back"].orEmpty(), { useForm = false; error = "" }, Modifier.fillMaxWidth())
                TypedCodeButton(nav, s)
                ActionButton(s["useCode"].orEmpty(), { useCode = true }, Modifier.fillMaxWidth())
                ActionButton(s["changeServer"].orEmpty(), nav::changeServer, Modifier.fillMaxWidth())
            }
        }
    }
}
