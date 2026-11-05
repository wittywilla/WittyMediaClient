package com.wittywilla.wittymediaclient.ui

import android.view.KeyEvent
import androidx.compose.foundation.background
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import com.wittywilla.wittymediaclient.data.LogoCache
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
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.IOException

// The screens in docs/APP-DESIGN.md, "Signing in", numbered as there. The words are the shared ones in
// shared/data/strings.en.json.

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

// The server's help on a forgotten password: inside the app, or on a TV a QR card to it.
const val FORGOT_PASSWORD_PATH = "/help/accounts#if-you-forget-your-password"

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

private val ARROWS = setOf(KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_DPAD_DOWN, KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_DPAD_RIGHT)
private const val NONE_AFTER_MS = 6000L

// A little more room in a column than its usual spacing.
@Composable
private fun Gap(size: Int) = Spacer(Modifier.height(LocalMetrics.current.u(size)))

// 1 and 2. Choose your server, or enter its address.
@Composable
fun ConnectScreen(nav: Nav, s: Map<String, String>, message: String) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val recent = remember { nav.app.store.recent }
    val appVersion = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty() }
    var address by rememberSaveable { mutableStateOf("") }
    var problem by rememberSaveable(message) { mutableStateOf(message) }
    var connecting by remember { mutableStateOf<String?>(null) }
    var showForm by rememberSaveable { mutableStateOf(false) }
    var found by remember { mutableStateOf(emptyList<FoundServer>()) }
    var searchedLong by remember { mutableStateOf(false) }
    var cantSearch by remember { mutableStateOf(false) }
    var moved by remember { mutableStateOf(false) }

    // Only looks while this screen is open.
    DisposableEffect(Unit) {
        val finder = ServerFinder(context, onCantSearch = { cantSearch = true }) { found = it }
        finder.start()
        onDispose { finder.stop() }
    }
    LaunchedEffect(Unit) {
        delay(NONE_AFTER_MS)
        searchedLong = true
    }

    fun connect(url: String) {
        if (connecting != null) return
        connecting = url
        problem = ""
        scope.launch {
            val failed = when (val r = probeServer(url, appVersion)) {
                is Probe.Found -> nav.arrive(r.url, r.status)
                is Probe.Failed -> reasonText(s, r.reason)
            }
            if (failed != null) {
                problem = failed
                address = url
                showForm = true
            }
            connecting = null
        }
    }

    fun submit() {
        when (val r = Address.normalize(address)) {
            is Address.Result.Ok -> connect(r.url)
            is Address.Result.Bad -> problem = reasonText(s, r.reason)
        }
    }

    if (showForm) {
        AddressScreen(nav, s, address, { address = it; problem = "" }, problem, connecting != null, ::submit) { showForm = false; problem = "" }
        return
    }

    val tv = LocalMetrics.current.tv
    val last = recent.firstOrNull()
    // A found server that's also saved shows only under Used before, with its own name and logo.
    val foundOnly = found.filter { f -> recent.none { it.url == f.url || (it.serverId.isNotEmpty() && it.serverId == f.id) } }
    val nothing = found.isEmpty() && recent.isEmpty()
    val metrics = LocalMetrics.current
    // The first server found takes focus, until the person has moved themselves.
    val noticeMoves = Modifier.onPreviewKeyEvent {
        if (it.type == KeyEventType.KeyDown && it.key.nativeKeyCode in ARROWS) moved = true
        false
    }
    SignInLayout(
        words = {
            Lockup("", null, app = true)
            SignInHeading(s["findTitle"].orEmpty(), detail = s["findSubtitle"].orEmpty(), display = true)
            Problem(problem, Modifier.fillMaxWidth())
        },
        actions = {
            Column(noticeMoves.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(metrics.u(12))) {
                SectionLabel(s["foundServers"].orEmpty(), searching = !cantSearch && !searchedLong)
                if (found.isEmpty()) {
                    when {
                        cantSearch -> Note(s["findNotSupported"].orEmpty())
                        searchedLong -> Note(s["findNone"].orEmpty())
                        else -> Note(s["findSearching"].orEmpty(), busy = true)
                    }
                }
                // Only where it is: a server says nothing about itself until it's added.
                foundOnly.forEachIndexed { i, server ->
                    key(server.id) {
                        ServerCard(
                            hostAndPort(server.url), s["foundOnNetwork"].orEmpty(), { connect(server.url) }, saved = false,
                            connecting = connecting == server.url, requestFocus = i == 0 && !moved, focusKey = "found-${server.id}",
                        )
                    }
                }
                if (recent.isNotEmpty()) {
                    SectionLabel(s["recentServers"].orEmpty(), Modifier.padding(top = metrics.u(8)))
                    recent.forEachIndexed { i, server ->
                        key(server.url) {
                            ServerCard(
                                server.name.ifEmpty { "WittyMediaServer" }, server.url, { connect(server.url) },
                                logo = LogoCache.file(context, server.url, server.brandLogo), lastUsed = server.url == last?.url,
                                connecting = connecting == server.url, requestFocus = foundOnly.isEmpty() && found.isNotEmpty() && i == 0 && !moved,
                                focusKey = "recent-${server.url}",
                            )
                        }
                    }
                }
            }
            WittyButton(
                s["enterAddress"].orEmpty(), { showForm = true; problem = "" }, Modifier.fillMaxWidth().padding(top = metrics.u(8)),
                kind = if (nothing) ButtonKind.Primary else ButtonKind.Secondary, icon = Symbols.Address, tall = true,
                requestFocus = found.isEmpty(), focusKey = "enter-address",
            )
            LegalNote(s["legalConnect"].orEmpty())
        },
    )
}

// Where a found server is: its host and port, which is all it's called until it's added.
fun hostAndPort(url: String): String {
    val parsed = url.toHttpUrlOrNull() ?: return url
    val usual = (parsed.scheme == "http" && parsed.port == 80) || (parsed.scheme == "https" && parsed.port == 443)
    return if (usual) parsed.host else "${parsed.host}:${parsed.port}"
}

// 2. Enter your server's address.
@Composable
private fun AddressScreen(
    nav: Nav,
    s: Map<String, String>,
    address: String,
    onChange: (String) -> Unit,
    problem: String,
    busy: Boolean,
    onSubmit: () -> Unit,
    onBack: () -> Unit,
) {
    val field = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { field.requestFocus() } }
    SignInLayout(
        onBack,
        words = {
            Lockup("", null, app = true)
            SignInHeading(s["addressTitle"].orEmpty(), detail = s["addressHint"].orEmpty())
        },
        actions = {
            WittyField(
                address, onChange, s["addressLabel"].orEmpty(), kind = FieldKind.Address, icon = Symbols.Address,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = field,
            )
            Problem(problem, Modifier.fillMaxWidth())
            WittyButton(s["connect"].orEmpty(), onSubmit, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true)
            LegalNote(s["legalConnect"].orEmpty())
        },
    )
}

// 3. Another machine is answering for a server we know. Only the person can decide, so the safe choice
// has focus, and nothing has been sent to it. No lockup: the name and logo would be that machine's.
@Composable
fun MismatchScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
    val metrics = LocalMetrics.current
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    SignInLayout(
        nav::pop,
        words = {
            WarningBadge(metrics.u(64), if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
            SignInHeading(s["identityTitle"].orEmpty(), detail = s["identityHint"].orEmpty())
            PanelCard {
                Text(server.url, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.label)
                Text(s["fingerprintLabel"].orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.caption)
                Text(server.fingerprint, color = MaterialTheme.colorScheme.onSurface, style = MaterialTheme.typography.secondary.copy(fontFamily = FontFamily.Monospace))
            }
        },
        actions = {
            Problem(problem, Modifier.fillMaxWidth())
            WittyButton(s["back"].orEmpty(), nav::pop, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, requestFocus = true)
            WittyButton(
                s["identityTrust"].orEmpty(),
                {
                    busy = true
                    scope.launch {
                        problem = nav.trust(server).orEmpty()
                        busy = false
                    }
                },
                Modifier.fillMaxWidth(), kind = ButtonKind.Destructive, busy = busy, tall = true,
            )
        },
    )
}

// 7. A new server is opened with a six-digit code from someone already signed in. See
// docs/CLIENT-API.md, "The code is typed on the device". The pad is on screen, as a remote has no
// keyboard; number keys type too.
@Composable
fun CodeScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
    val metrics = LocalMetrics.current
    var entry by remember { mutableStateOf(CodeEntry()) }
    var problem by remember { mutableStateOf("") }
    var wrong by remember { mutableIntStateOf(0) }

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
                wrong++
            }
        }
    }
    fun erase() { entry = entry.erased() }

    Box(Modifier.digitKeys(::press, ::erase)) {
        SignInLayout(
            nav::pop,
            words = {
                SignInHeading(s["codeTitle"].orEmpty(), detail = s["codeHint"].orEmpty())
                // Several servers can look alike in the list: this says which one the code goes to.
                ServerPill(server.name.ifEmpty { "WittyMediaServer" }, nav.brandLogo, if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
                CodeBoxes(entry.digits, entry.busy, wrong, if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
                // Room is kept for the message, or the keys would move under a finger as it comes and goes.
                Box(Modifier.heightIn(min = metrics.u(24))) {
                    if (entry.busy) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8))) {
                            Spinner(MaterialTheme.colorScheme.onSurfaceVariant, metrics.u(if (metrics.tv) 30 else 16))
                            Text(s["connecting"].orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
                        }
                    } else {
                        Problem(problem, Modifier.fillMaxWidth())
                    }
                }
            },
            actions = {
                NumberPad(::press, ::erase, Modifier.fillMaxWidth(), firstFocus = true)
                QuietLinks(stacked = true) {
                    WittyButton(s["usePassword"].orEmpty(), { nav.signInTo(server, SignInWay.Password) }, kind = ButtonKind.Quiet)
                    WittyButton(s["showCodeInstead"].orEmpty(), { nav.signInTo(server, SignInWay.ShownCode) }, kind = ButtonKind.Quiet)
                }
                Fingerprint(s, server.fingerprint)
            },
        )
    }
}

@Composable
private fun Fingerprint(s: Map<String, String>, fingerprint: String) {
    if (fingerprint.isEmpty()) return
    val caption = MaterialTheme.typography.caption.copy(fontWeight = FontWeight.Normal)
    Text(
        buildAnnotatedString {
            append("${s["fingerprintLabel"]}: ")
            withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(fingerprint) }
        },
        color = LocalExtraColours.current.hint, style = caption,
        textAlign = if (LocalMetrics.current.tv) TextAlign.Start else TextAlign.Center, modifier = Modifier.fillMaxWidth(),
    )
}

// Quiet buttons side by side where they fit and wrapping where they don't, centred in a column, to the left on
// a TV. `stacked`: further apart, one under the other when they don't both fit, as the code screen's are.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun QuietLinks(stacked: Boolean = false, content: @Composable () -> Unit) {
    val metrics = LocalMetrics.current
    FlowRow(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.u(if (stacked) 24 else 8), if (metrics.tv) Alignment.Start else Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(metrics.u(if (stacked) 0 else 8)),
    ) { content() }
}

// This server as itself at the foot of the screens that start signing in: its logo and name (larger on a TV,
// to read from the sofa), with Change server beside them.
@Composable
private fun ServerFooter(nav: Nav, s: Map<String, String>, centred: Boolean = !LocalMetrics.current.tv) {
    val metrics = LocalMetrics.current
    val name = nav.brandName.ifEmpty { nav.server?.name.orEmpty() }.ifEmpty { "WittyMediaServer" }
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(metrics.u(4), if (centred) Alignment.CenterHorizontally else Alignment.Start),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ServerMark(metrics.u(if (metrics.tv) 32 else 20), nav.brandLogo, Modifier.padding(end = metrics.u(4)))
        Text(
            name, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1,
            style = if (metrics.tv) MaterialTheme.typography.label.copy(fontWeight = FontWeight.Normal) else MaterialTheme.typography.secondary,
        )
        WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Quiet, focusKey = "change-server")
    }
}

// 8. The TV shows a code; someone already signed in on a phone or computer approves it, so nobody
// has to type a password with a remote. See docs/CLIENT-API.md.
@Composable
private fun PairScreen(nav: Nav, s: Map<String, String>, onBack: () -> Unit, onUsePassword: () -> Unit) {
    val metrics = LocalMetrics.current
    var round by remember { mutableIntStateOf(0) }
    var code by remember { mutableStateOf("") }
    var approveAt by remember { mutableStateOf("") }
    var scan by remember { mutableStateOf("") }
    var problem by remember { mutableStateOf("") }
    var waiting by remember { mutableStateOf(false) }
    // The server has given this device a lot of codes lately: a password is the way in for now.
    var limited by remember { mutableStateOf(false) }

    LaunchedEffect(round) {
        code = ""
        problem = ""
        waiting = false
        limited = false
        try {
            val start = try {
                nav.app.api.pairStart(nav.app.deviceName, nav.app.platformName)
            } catch (e: ApiError) {
                if (e.status != 429) throw e
                limited = true
                problem = s["pairBusy"].orEmpty()
                return@LaunchedEffect
            }
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

    val ended = code.isEmpty() && problem.isNotEmpty()
    val spacing = with(LocalDensity.current) { metrics.u(if (metrics.tv) 16 else 8).toSp() }
    val codeSize = with(LocalDensity.current) { metrics.u(if (metrics.tv) 72 else 40).toSp() }
    SignInLayout(
        onBack,
        words = {
            Lockup(nav.brandName, nav.brandLogo)
            SignInHeading(s["pairTitle"].orEmpty(), detail = if (code.isNotEmpty()) s["pairHint"].orEmpty() else "")
            val place = if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally)
            if (code.isNotEmpty()) {
                SelectionContainer(place) {
                    Text(approveAt, color = LocalExtraColours.current.accentText, style = MaterialTheme.typography.label, textAlign = if (metrics.tv) TextAlign.Start else TextAlign.Center)
                }
                Text(
                    code, color = MaterialTheme.colorScheme.onSurface,
                    style = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = codeSize, letterSpacing = spacing),
                    modifier = place
                        .clip(metrics.corner(14))
                        .background(MaterialTheme.colorScheme.surface)
                        .padding(horizontal = metrics.u(24), vertical = metrics.u(12))
                        .semantics { contentDescription = code.toList().joinToString(" ") },
                )
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(metrics.u(8)), modifier = place) {
                    Spinner(MaterialTheme.colorScheme.onSurfaceVariant, metrics.u(if (metrics.tv) 30 else 16))
                    Text(if (waiting) s["errLost"].orEmpty() else s["pairWaiting"].orEmpty(), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary)
                }
            } else if (!ended) {
                Box(place.heightIn(min = metrics.u(80)), contentAlignment = Alignment.Center) {
                    Spinner(MaterialTheme.colorScheme.onSurfaceVariant, metrics.u(if (metrics.tv) 40 else 24))
                }
            }
            Problem(problem, Modifier.fillMaxWidth())
        },
        actions = {
            if (code.isNotEmpty() && scan.isNotEmpty()) QrCard(scan, s["pairScan"].orEmpty(), if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
            if (ended) {
                if (limited) WittyButton(s["usePassword"].orEmpty(), onUsePassword, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-password")
                else WittyButton(s["pairNew"].orEmpty(), { round++ }, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-new")
            }
            QuietLinks {
                val server = nav.server
                if (server != null && server.publicKey.isNotEmpty()) {
                    WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Quiet, focusKey = "typed-code")
                }
                if (!limited) WittyButton(s["usePassword"].orEmpty(), onUsePassword, kind = ButtonKind.Quiet, requestFocus = code.isNotEmpty(), focusKey = "use-password")
                WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Quiet, focusKey = "change-server")
            }
        },
    )
}

private enum class Step { Usual, Form, Password, Pair }

// Where a password was typed, for the words when it's refused.
private enum class Typed { Tile, Password, Form }

// 4, 5 and 6: who's watching, a profile's password, and the sign-in form, with the two-factor step
// when an account asks for it. 8 too, as a way of signing in from here.
@Composable
fun SignInScreen(nav: Nav, s: Map<String, String>, way: SignInWay) {
    val scope = rememberCoroutineScope()
    // On a TV the code comes first. Everywhere else a keyboard is at hand.
    val codeFirst = way == SignInWay.ShownCode || (way == SignInWay.Usual && nav.app.isTv)
    var step by rememberSaveable { mutableStateOf(if (codeFirst) Step.Pair else Step.Usual) }
    var pairFrom by rememberSaveable { mutableStateOf<Step?>(null) }
    var profiles by remember { mutableStateOf<Profiles?>(null) }
    var chosenId by rememberSaveable { mutableStateOf<Long?>(null) }
    var name by rememberSaveable { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    // A wrong password: its field is red until the person types again, and shakes once each time.
    var refused by remember { mutableStateOf(false) }
    var wrongPasswords by remember { mutableIntStateOf(0) }
    // The second step: the password was right, and the account wants its authenticator's code too,
    // or one of its recovery codes.
    var secondStep by remember { mutableStateOf(false) }
    var code by remember { mutableStateOf("") }
    var useRecovery by remember { mutableStateOf(false) }
    var recovery by remember { mutableStateOf("") }
    var wrong by remember { mutableIntStateOf(0) }
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        profiles = runCatching { nav.app.api.profiles() }.getOrDefault(Profiles())
    }

    fun login(who: String, secret: String, typed: String = "", from: Typed = Typed.Password) {
        if (busy) return
        busy = true
        problem = ""
        scope.launch {
            try {
                val stopped = nav.server?.let { nav.clearToSend(it) }
                if (stopped != null) {
                    problem = stopped
                } else {
                    val result = nav.app.api.login(who, secret, nav.app.deviceName, typed)
                    if (result.token.isEmpty()) problem = s["errInvalid"].orEmpty() else nav.signedIn(result.token, result.user)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: ApiError) {
                when {
                    e.twoFactor -> {
                        // The first answer only asks; after a code it says that one was wrong.
                        if (typed.isNotEmpty()) {
                            problem = s[if (useRecovery) "errWrongRecovery" else "errWrongCode"].orEmpty()
                            wrong++
                            if (useRecovery) recovery = ""
                        }
                        secondStep = true
                        code = ""
                    }
                    // Cleared and asked for again, as every phone does: no one fixes a password they can't see.
                    e.status == 401 && from != Typed.Tile -> {
                        problem = s[if (from == Typed.Form) "errWrongNameOrPassword" else "errWrongPassword"].orEmpty()
                        password = ""
                        refused = true
                        wrongPasswords++
                    }
                    // Too many tries (429) says how long to wait, in the server's own words.
                    else -> problem = problemWords(e, s["errLost"].orEmpty())
                }
            } catch (e: Exception) {
                problem = problemWords(e, s["errLost"].orEmpty())
                code = ""
            } finally {
                busy = false
            }
        }
    }

    fun back(to: Step) {
        step = to
        problem = ""
        password = ""
        refused = false
        secondStep = false
        useRecovery = false
        recovery = ""
        code = ""
    }

    fun openPair() {
        pairFrom = step
        back(Step.Pair)
    }

    val list = profiles
    val showsProfiles = list != null && list.style == "profiles" && list.profiles.isNotEmpty()
    val chosen = list?.profiles?.firstOrNull { it.id == chosenId }
    val signingInAs = chosen?.name ?: name
    // Each step remembers its own focus, so a step's first focus isn't lost to another's, and coming
    // back to one, as from the help, puts focus where it was. Kept with the app's screens.
    val memory = nav.focusFor("signin-step-" + if (secondStep) "two-factor" else step.name)
    CompositionLocalProvider(LocalFocusMemory provides memory) {
        when {
            step == Step.Pair -> PairScreen(nav, s, onBack = { back(pairFrom ?: Step.Usual) }) { back(pairFrom ?: Step.Usual) }
            list == null -> Screen { Loading() }
            secondStep -> TwoFactorStep(
                nav, s, chosen, code,
                onCode = { typed ->
                    code = typed.filter { it.isDigit() }.take(CODE_LENGTH)
                    problem = ""
                    if (code.length == CODE_LENGTH) login(signingInAs, password, code)
                },
                checking = busy, wrong = wrong, problem = problem,
                useRecovery = useRecovery, recovery = recovery,
                onRecovery = { recovery = it; problem = "" },
                onSubmitRecovery = { if (recovery.isNotBlank()) login(signingInAs, password, recovery.trim()) },
                onSwitch = { useRecovery = !useRecovery; recovery = ""; code = ""; problem = "" },
                onBack = { secondStep = false; useRecovery = false; recovery = ""; code = ""; problem = "" },
            )
            step == Step.Password && chosen != null -> PasswordStep(
                nav, s, chosen, password, { password = it; problem = ""; refused = false }, problem, busy, refused, wrongPasswords,
                onSubmit = { login(chosen.name, password) },
                onBack = { back(Step.Usual) },
            )
            showsProfiles && step == Step.Usual -> WhoStep(
                nav, s, list.profiles, problem, busy,
                onPick = { p ->
                    problem = ""
                    if (p.hasPassword) {
                        chosenId = p.id
                        step = Step.Password
                    } else {
                        login(p.name, "", from = Typed.Tile)
                    }
                },
                onOtherAccount = { back(Step.Form) },
                onUseCode = ::openPair,
            )
            else -> FormStep(
                nav, s, name, { name = it; problem = ""; refused = false }, password, { password = it; problem = ""; refused = false },
                problem, busy, refused, wrongPasswords,
                onSubmit = { login(name, password, from = Typed.Form) },
                onBack = if (showsProfiles) { { back(Step.Usual) } } else null,
                onUseCode = ::openPair,
            )
        }
    }
}

// The quiet ways to sign in without a password here.
@Composable
private fun CodeLinks(nav: Nav, s: Map<String, String>, onUseCode: () -> Unit, otherAccount: (() -> Unit)? = null) {
    QuietLinks {
        if (otherAccount != null) WittyButton(s["otherAccount"].orEmpty(), otherAccount, kind = ButtonKind.Quiet, focusKey = "other-account")
        WittyButton(s["useCode"].orEmpty(), onUseCode, kind = ButtonKind.Quiet, focusKey = "use-code")
        // Only a server that has proved its identity can be sent a code.
        val server = nav.server
        if (server != null && server.publicKey.isNotEmpty()) {
            WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Quiet, focusKey = "typed-code")
        }
    }
}

// 4. Who's watching? Profiles as faces, two across on a phone and as many as fit on a tablet. A TV has
// them in one centred row.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WhoStep(
    nav: Nav,
    s: Map<String, String>,
    profiles: List<Profile>,
    problem: String,
    busy: Boolean,
    onPick: (Profile) -> Unit,
    onOtherAccount: () -> Unit,
    onUseCode: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val size = metrics.u(
        when {
            metrics.tv -> 200
            metrics.tablet -> 140
            else -> 104
        },
    )
    val tiles: @Composable () -> Unit = {
        profiles.forEachIndexed { i, p ->
            key(p.id) { ProfileTile(p, size, { if (!busy) onPick(p) }, requestFocus = i == 0, focusKey = "profile-${p.id}") }
        }
    }
    // Wrapping rather than scrolling, so nothing clips a lifted, ringed avatar.
    val grid: @Composable () -> Unit = {
        FlowRow(
            Modifier.fillMaxWidth().remoteRow(),
            horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 48 else 24), Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(metrics.u(28)),
            maxItemsInEachRow = if (metrics.tv || metrics.tablet) Int.MAX_VALUE else 2,
        ) { tiles() }
    }
    if (metrics.tv) {
        // Everything centred, as on Apple TV: the lockup, the title, the faces, the other ways in in one row,
        // then this server.
        val accent = MaterialTheme.colorScheme.primary
        Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).signInGlow(accent), contentAlignment = Alignment.Center) {
            Column(
                Modifier.padding(horizontal = metrics.gutter + metrics.tvSafeSides),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(metrics.u(40)),
            ) {
                Lockup(nav.brandName, nav.brandLogo)
                SignInHeading(s["whoTitle"].orEmpty(), display = true, centred = true)
                if (problem.isNotEmpty()) Problem(problem, centred = true)
                grid()
                Row(Modifier.remoteRow(), horizontalArrangement = Arrangement.spacedBy(metrics.u(24))) {
                    WittyButton(s["otherAccount"].orEmpty(), onOtherAccount, kind = ButtonKind.Quiet, focusKey = "other-account")
                    WittyButton(s["useCode"].orEmpty(), onUseCode, kind = ButtonKind.Quiet, focusKey = "use-code")
                    val server = nav.server
                    if (server != null && server.publicKey.isNotEmpty()) {
                        WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Quiet, focusKey = "typed-code")
                    }
                }
                ServerFooter(nav, s, centred = true)
            }
        }
        return
    }
    SignInPage(wide = metrics.tablet) {
        Lockup(nav.brandName, nav.brandLogo)
        SignInHeading(s["whoTitle"].orEmpty(), display = true)
        Gap(8)
        grid()
        Gap(8)
        Problem(problem, Modifier.fillMaxWidth())
        CodeLinks(nav, s, onUseCode, onOtherAccount)
        ServerFooter(nav, s)
    }
}

// 5. A profile's password, under its face. A wrong one clears the field, keeps focus in it, turns it red
// and shakes it once.
@Composable
private fun PasswordStep(
    nav: Nav,
    s: Map<String, String>,
    who: Profile,
    password: String,
    onChange: (String) -> Unit,
    problem: String,
    busy: Boolean,
    refused: Boolean,
    wrongPasswords: Int,
    onSubmit: () -> Unit,
    onBack: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val field = remember { FocusRequester() }
    // On the first look; coming back, as from the help, focus goes back where it was.
    val firstLook = LocalFocusMemory.current.last == null
    LaunchedEffect(who.id) { if (firstLook) runCatching { field.requestFocus() } }
    LaunchedEffect(wrongPasswords) { if (wrongPasswords > 0) runCatching { field.requestFocus() } }
    // One centred column on every device, TVs included: the face with its names centred under it, then the way in.
    SignInLayout(
        onBack, centred = true,
        words = {
            FaceWithNames(who, metrics.u(if (metrics.tv) 200 else 120), Modifier.align(Alignment.CenterHorizontally))
            SignInHeading("", detail = s["passwordHint"].orEmpty(), centred = true)
        },
        actions = {
            WittyField(
                password, onChange, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = field, isError = refused, shake = wrongPasswords,
            )
            Problem(problem, Modifier.fillMaxWidth())
            WittyButton(s["signIn"].orEmpty(), onSubmit, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true)
            ForgotPassword(nav, s, Modifier.align(Alignment.CenterHorizontally))
        },
    )
}

// docs/APP-DESIGN.md, Avatar 5: wherever a face shows with its names, they're centred under it.
@Composable
fun FaceWithNames(who: Profile, size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val shown = avatarName(who.displayName, who.name)
    Column(modifier.width(IntrinsicSize.Max).widthIn(min = size), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        Avatar(shown, size, Modifier.padding(bottom = metrics.u(if (metrics.tv) 8 else 0)))
        Text(shown, color = MaterialTheme.colorScheme.onBackground, style = MaterialTheme.typography.headline, textAlign = TextAlign.Center, maxLines = 1)
        if (showsUsername(who.displayName, who.name)) {
            Text("@${who.name}", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.secondary, textAlign = TextAlign.Center)
        }
    }
}

@Composable
private fun ForgotPassword(nav: Nav, s: Map<String, String>, modifier: Modifier = Modifier) {
    val words = s["forgotPassword"].orEmpty()
    WittyButton(
        words,
        { nav.push(if (nav.app.isTv) Route.OnPhone(words, FORGOT_PASSWORD_PATH) else Route.Help(FORGOT_PASSWORD_PATH)) },
        modifier, kind = ButtonKind.Quiet, focusKey = "forgot-password",
    )
}

// 6. Sign in with a username and password. Refused, both fields turn red and the password is asked for again.
@Composable
private fun FormStep(
    nav: Nav,
    s: Map<String, String>,
    name: String,
    onName: (String) -> Unit,
    password: String,
    onPassword: (String) -> Unit,
    problem: String,
    busy: Boolean,
    refused: Boolean,
    wrongPasswords: Int,
    onSubmit: () -> Unit,
    onBack: (() -> Unit)?,
    onUseCode: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val first = remember { FocusRequester() }
    val second = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (!metrics.tv) runCatching { first.requestFocus() } }
    LaunchedEffect(wrongPasswords) { if (wrongPasswords > 0) runCatching { second.requestFocus() } }
    SignInLayout(
        onBack,
        words = {
            Lockup(nav.brandName, nav.brandLogo)
            SignInHeading(s["signInTitle"].orEmpty())
        },
        actions = {
            WittyField(
                name, onName, s["usernameLabel"].orEmpty(), kind = FieldKind.Username, icon = Symbols.Person,
                imeAction = ImeAction.Next, onAction = { runCatching { second.requestFocus() } }, focusRequester = first,
                isError = refused, shake = wrongPasswords,
            )
            WittyField(
                password, onPassword, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = second, isError = refused, shake = wrongPasswords,
            )
            Problem(problem, Modifier.fillMaxWidth())
            WittyButton(s["signIn"].orEmpty(), onSubmit, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = busy, tall = true, requestFocus = metrics.tv, focusKey = "sign-in")
            CodeLinks(nav, s, onUseCode)
            ServerFooter(nav, s)
        },
    )
}

// 5, second step: the six digits from an authenticator app. A phone types them with its own number
// keyboard, which can fill in a code it was sent; a TV has the pad. Or, for a lost phone, a recovery code.
@Composable
private fun TwoFactorStep(
    nav: Nav,
    s: Map<String, String>,
    who: Profile?,
    code: String,
    onCode: (String) -> Unit,
    checking: Boolean,
    wrong: Int,
    problem: String,
    useRecovery: Boolean,
    recovery: String,
    onRecovery: (String) -> Unit,
    onSubmitRecovery: () -> Unit,
    onSwitch: () -> Unit,
    onBack: () -> Unit,
) {
    val metrics = LocalMetrics.current
    val field = remember { FocusRequester() }
    val recoveryField = remember { FocusRequester() }
    LaunchedEffect(useRecovery) {
        if (useRecovery) runCatching { recoveryField.requestFocus() } else if (!metrics.tv) runCatching { field.requestFocus() }
    }
    val press = { digit: Char -> if (!checking && !useRecovery) onCode(code + digit) }
    val erase = { if (!checking && !useRecovery) onCode(code.dropLast(1)) }
    val switch: @Composable (Modifier) -> Unit = { modifier ->
        WittyButton(
            s[if (useRecovery) "useAuthenticatorCode" else "useRecoveryCode"].orEmpty(), onSwitch, modifier,
            kind = ButtonKind.Quiet, focusKey = "recovery-switch",
        )
    }
    Box(if (useRecovery) Modifier else Modifier.digitKeys(press, erase)) {
        SignInLayout(
            onBack,
            words = {
                val centre = if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally)
                if (who != null) Avatar(avatarName(who.displayName, who.name), metrics.u(if (metrics.tv) 200 else 120), centre)
                else Lockup(nav.brandName, nav.brandLogo, centre)
                if (useRecovery) {
                    SignInHeading(s["recoveryTitle"].orEmpty(), detail = s["recoveryHint"].orEmpty())
                } else {
                    SignInHeading(s["twoFactorTitle"].orEmpty())
                    Note(s["twoFactorHint"].orEmpty())
                    Box(centre) {
                        CodeBoxes(code, checking, wrong)
                        if (!metrics.tv) {
                            // What the keyboard types into, under the boxes: they show it.
                            BasicTextField(
                                code, { if (!checking) onCode(it) },
                                singleLine = true,
                                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword, imeAction = ImeAction.Done),
                                modifier = Modifier
                                    .matchParentSize()
                                    .graphicsLayer { alpha = 0f }
                                    .focusRequester(field)
                                    .semantics { contentType = ContentType.SmsOtpCode },
                            )
                        }
                    }
                    Problem(problem, Modifier.fillMaxWidth())
                }
            },
            actions = {
                if (useRecovery) {
                    WittyField(
                        recovery, onRecovery, s["recoveryLabel"].orEmpty(), icon = Symbols.Key, imeAction = ImeAction.Go,
                        onAction = onSubmitRecovery, focusRequester = recoveryField, isError = problem.isNotEmpty(), shake = wrong, maxLength = RECOVERY_MOST,
                    )
                    Problem(problem, Modifier.fillMaxWidth())
                    WittyButton(s["signIn"].orEmpty(), onSubmitRecovery, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, busy = checking, tall = true)
                } else if (metrics.tv) {
                    NumberPad(press, erase, Modifier.fillMaxWidth(), firstFocus = true)
                }
                switch(if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
            },
        )
    }
}

// The server takes at most 32 characters of a code.
private const val RECOVERY_MOST = 32

// What a TV doesn't open itself, such as the help on a forgotten password: a QR card for a phone, with
// the address under it, as Apple TV has.
@Composable
fun OnPhoneScreen(nav: Nav, s: Map<String, String>, title: String, path: String) {
    val metrics = LocalMetrics.current
    val address = remember(path) { runCatching { nav.app.api.mediaUrl(path) }.getOrDefault("") }
    SignInLayout(
        nav::pop,
        words = {
            SignInHeading(title, detail = s["openOnPhone"].orEmpty())
        },
        actions = {
            if (address.isNotEmpty()) QrCard(address, address, if (metrics.tv) Modifier else Modifier.align(Alignment.CenterHorizontally))
            WittyButton(s["back"].orEmpty(), nav::pop, Modifier.fillMaxWidth(), kind = ButtonKind.Primary, tall = true, takeFocus = true)
        },
    )
}
