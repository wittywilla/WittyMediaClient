// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 WittyWilla and contributors
package com.wittywilla.wittymediaclient.ui

import android.Manifest
import android.view.KeyEvent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
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
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.autofill.ContentType
import androidx.compose.ui.draw.clip
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
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.contentType
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.em
import com.wittywilla.wittymediaclient.data.LogoCache
import com.wittywilla.wittymediaclient.data.SavedServer
import com.wittywilla.wittymediaclient.data.addressNow
import com.wittywilla.wittymediaclient.data.fill
import com.wittywilla.wittymediaclient.data.focusAfterRemoval
import com.wittywilla.wittymediaclient.data.isStale
import com.wittywilla.wittymediaclient.data.oldEntryFor
import com.wittywilla.wittymediaclient.data.reachedWords
import com.wittywilla.wittymediaclient.data.shownName
import com.wittywilla.wittymediaclient.net.Address
import com.wittywilla.wittymediaclient.net.ApiError
import com.wittywilla.wittymediaclient.net.FoundServer
import com.wittywilla.wittymediaclient.net.PeerRules
import com.wittywilla.wittymediaclient.net.Probe
import com.wittywilla.wittymediaclient.net.Profile
import com.wittywilla.wittymediaclient.net.Profiles
import com.wittywilla.wittymediaclient.net.ServerFinder
import com.wittywilla.wittymediaclient.net.probeServer
import com.wittywilla.wittymediaclient.net.problemWords
import com.wittywilla.wittymediaclient.net.screenFor
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

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

// 1 and 2. Choose your server, or enter its address.
@Composable
fun ConnectScreen(nav: Nav, s: Map<String, String>, message: String) {
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var recent by remember { mutableStateOf(nav.app.store.recent) }
    val memory = LocalFocusMemory.current
    // Removing remembered servers: Edit's buttons, a card's menu (a phone), the question a TV asks first, and
    // which card takes focus when the one that had it is gone.
    var editing by rememberSaveable { mutableStateOf(false) }
    var menuFor by remember { mutableStateOf<SavedServer?>(null) }
    var asking by remember { mutableStateOf<SavedServer?>(null) }
    var focusOn by remember { mutableStateOf<String?>(null) }
    val now = remember(recent) { System.currentTimeMillis() }
    // Focus kept for a card that isn't in the list any more, or for Edit or Manage servers when the last server
    // has gone and they with it, would leave a remote with no focus at all.
    val lost = memory.last?.let { key ->
        (key.startsWith("recent-") && recent.none { "recent-${it.url}" == key }) || (recent.isEmpty() && (key == "manage-servers" || key == "edit-servers"))
    } == true
    if (lost) memory.last = null
    DisposableEffect(Unit) { onDispose { nav.pickerNotice = "" } }
    val appVersion = remember { runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull().orEmpty() }
    var address by rememberSaveable { mutableStateOf("") }
    var problem by rememberSaveable(message) { mutableStateOf(message) }
    var connecting by remember { mutableStateOf<String?>(null) }
    var showForm by rememberSaveable { mutableStateOf(false) }
    var found by remember { mutableStateOf(emptyList<FoundServer>()) }
    var searchedLong by remember { mutableStateOf(false) }
    var cantSearch by remember { mutableStateOf(false) }
    var moved by remember { mutableStateOf(false) }
    // A server whose first-time setup isn't done (setup is web-only): its address, for the screen that says so.
    var notSetUp by remember { mutableStateOf<String?>(null) }

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
        nav.pickerNotice = ""
        scope.launch {
            val failed = when (val r = probeServer(url, appVersion)) {
                is Probe.Found -> nav.arrive(r.url, r.status)
                // A server this device knows that doesn't answer here may be reached from away.
                is Probe.Failed -> {
                    val saved = recent.firstOrNull { it.url == url }
                    if (r.reason == "unreachable" && saved != null && nav.app.peers.info(saved) != null) {
                        problem = s["awayConnecting"].orEmpty()
                        if (nav.tryFromAway(saved)) null else s["errAwayFailed"].orEmpty()
                    } else if (r.reason == "not-set-up") {
                        notSetUp = url
                        null
                    } else reasonText(s, r.reason)
                }
            }
            if (failed != null) {
                problem = failed
                address = url
                showForm = true
            }
            connecting = null
        }
    }

    // The camera, for a QR code: asked about first, never on a TV or a device without one.
    var scan by remember { mutableStateOf(ConnectScan.Off) }
    val canScan = remember { !nav.app.isTv && hasCamera(context) }
    val cameraAsk = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        scan = if (granted) ConnectScan.On else ConnectScan.Denied
    }

    fun submit() {
        // An invite link from the server's Remote Access page, for connecting from away.
        PeerRules.invite(address)?.let { invite ->
            if (connecting != null) return
            connecting = "invite"
            problem = ""
            scope.launch {
                nav.joinInvite(invite)?.let { problem = it }
                connecting = null
            }
            return
        }
        when (val r = Address.normalize(address)) {
            is Address.Result.Ok -> connect(r.url)
            is Address.Result.Bad -> problem = reasonText(s, r.reason)
        }
    }

    notSetUp?.let { at ->
        SetupRequiredScreen(s, at, retry = { notSetUp = null; connect(at) }, back = { notSetUp = null })
        return
    }

    if (showForm) {
        AddressScreen(nav, s, address, { address = it; problem = "" }, problem, connecting != null, ::submit) { showForm = false; problem = "" }
        return
    }

    // Reading a QR code with the camera: an invite from the server's Remote Access page, or a server's address.
    if (scan != ConnectScan.Off) {
        DesignScreen(s["remoteScanCard"].orEmpty(), { scan = ConnectScan.Off }, eyebrow = s["remoteTitle"].orEmpty(), tag = "scan-code",
            actions = { WittyButton(s["remoteAddressCard"].orEmpty(), { scan = ConnectScan.Off; showForm = true }, kind = ButtonKind.Secondary, tall = true) },
        ) {
            DesignSection("") {
                when (scan) {
                    ConnectScan.Why -> {
                        DesignNote(s["remoteCameraWhy"].orEmpty(), tone = true)
                        DesignActions {
                            WittyButton(s["approveCameraAllow"].orEmpty(), { cameraAsk.launch(Manifest.permission.CAMERA) }, kind = ButtonKind.Primary, tall = true, requestFocus = true)
                        }
                    }
                    ConnectScan.Denied -> DesignNote(s["remoteCameraDenied"].orEmpty(), tone = true)
                    else -> {
                        DesignNote(s["remoteScanning"].orEmpty())
                        QrScanner(s["remoteScanning"].orEmpty(), { text ->
                            if (scan != ConnectScan.On) return@QrScanner
                            val read = text.trim()
                            when {
                                PeerRules.invite(read) != null || Address.normalize(read) is Address.Result.Ok -> { scan = ConnectScan.Off; address = read; submit() }
                                else -> problem = s["remoteScanNotOurs"].orEmpty()
                            }
                        }, onFailed = { scan = ConnectScan.Off; problem = s["approveCameraFailed"].orEmpty() })
                    }
                }
                DesignNote(problem, error = true)
            }
        }
        return
    }

    val tv = LocalMetrics.current.tv
    val last = recent.firstOrNull()
    // A found server that's also saved shows only under Used before, with its own name and logo.
    val foundOnly = found.filter { f -> recent.none { it.url == f.url || (it.serverId.isNotEmpty() && it.serverId == f.id) } }

    // Off this device at once, with Undo, on a phone or tablet; a TV has asked first. Focus goes to the next
    // card, else the one before, else Enter an address: never nowhere.
    fun remove(server: SavedServer) {
        val cards = foundOnly.map { "found-${it.id}" } + recent.map { "recent-${it.url}" }
        val next = focusAfterRemoval(cards, "recent-${server.url}") ?: "enter-address"
        nav.forgetServer(server, undoable = !tv)
        if (tv) nav.pickerNotice = fill(s["removedServer"], "name" to shownName(server))
        recent = nav.app.store.recent
        if (recent.isEmpty()) editing = false
        memory.last = next
        scope.launch {
            focusOn = null
            withFrameNanos { }
            focusOn = next
        }
    }
    val nothing = found.isEmpty() && recent.isEmpty()
    val metrics = LocalMetrics.current
    // The first server found takes focus, until the person has moved themselves.
    val noticeMoves = Modifier.onPreviewKeyEvent {
        if (it.type == KeyEventType.KeyDown && it.key.nativeKeyCode in ARROWS) moved = true
        false
    }
    var savedFirst by remember { mutableStateOf(nav.app.store.savedFirst) }
    // On a TV, the first card takes focus: the server used last, else the first one found, else Enter an address. As
    // servers are found after the screen opens, focus follows the first of them until the person moves it themselves,
    // so it never stays on Enter an address below a long list.
    val firstKey = when {
        recent.isNotEmpty() && (savedFirst || foundOnly.isEmpty()) -> "recent-${recent[0].url}"
        foundOnly.isNotEmpty() -> "found-${foundOnly[0].id}"
        else -> "enter-address"
    }
    LaunchedEffect(firstKey) {
        if (!tv || moved || editing) return@LaunchedEffect
        val at = memory.last
        if (at != null && at != "enter-address" && !at.startsWith("found-")) return@LaunchedEffect
        focusOn = null
        withFrameNanos { }
        focusOn = firstKey
    }
    Box(Modifier.fillMaxSize()) {
        // Design 2's connect page (the canvas's `connect`): the servers this device has used, those found on the network,
        // then the ways to reach a server that isn't here (peer to peer, a QR code, an address), then this device's servers.
        DesignPage(
            s["findTitle"].orEmpty(), lead = s["findSubtitle"].orEmpty(), foot = s["legalConnect"].orEmpty(), tag = "connect",
            top = { Lockup("", null, app = true) }, centred = !tv,
        ) {
            DesignNote(problem, Modifier.padding(top = LocalDesignSizes.current.gap), error = true)
            Notice(nav.pickerNotice, Modifier.padding(top = LocalDesignSizes.current.gap))
            Column(noticeMoves.fillMaxWidth()) {
                // Saved servers first (the setting under Servers on this device, on unless turned off): what this device
                // has used is on top, the last used first, so a long list found on the network never pushes it out of
                // sight. Off, the found servers come first, as before.
                val foundBlock = @Composable {
                    ConnectSection(s["foundServers"].orEmpty()) {
                        if (found.isEmpty()) {
                            when {
                                cantSearch -> DesignNote(s["findNotSupported"].orEmpty())
                                searchedLong -> DesignNote(s["findNone"].orEmpty())
                                else -> DesignNote(s["findSearching"].orEmpty(), busy = true)
                            }
                        } else if (!cantSearch && !searchedLong) {
                            // Still looking: more may come.
                            DesignNote(s["findSearching"].orEmpty(), busy = true)
                        }
                        // Only where it is: a server says nothing about itself until it's added.
                        foundOnly.forEachIndexed { i, server ->
                            key(server.id) {
                                ServerCard(
                                    hostAndPort(server.url), s["foundOnNetwork"].orEmpty(), { connect(server.url) }, saved = false, lineIcon = LineIcons.Wifi,
                                    connecting = connecting == server.url, requestFocus = i == 0 && !moved && (!savedFirst || recent.isEmpty()), focusKey = "found-${server.id}",
                                    takeFocus = focusOn == "found-${server.id}",
                                )
                            }
                        }
                    }
                }
                val savedBlock = @Composable {
                    if (recent.isNotEmpty()) {
                        ConnectSection(s["recentServers"].orEmpty()) {
                            recent.forEachIndexed { i, server ->
                                key(server.url) {
                                    val name = shownName(server)
                                    // Where it's announcing itself now, if that's somewhere new. It still has to prove its key there.
                                    val at = addressNow(server, found)
                                    val removeLabel = fill(s["removeServerNamed"], "name" to name)
                                    val card = @Composable {
                                        Box {
                                            // A server reached peer to peer says so, rather than its private address.
                                            val viaPeer = PeerRules.isAwayOnlyUrl(server.url) || nav.app.peers.info(server) != null
                                            ServerCard(
                                                name, if (viaPeer) s["savedPeer"].orEmpty() else server.url, { connect(at) },
                                                logo = LogoCache.file(context, server.url, server.brandLogo), lastUsed = server.url == last?.url,
                                                connecting = connecting == at, requestFocus = i == 0 && !moved && (savedFirst || (foundOnly.isEmpty() && found.isNotEmpty())),
                                                focusKey = "recent-${server.url}",
                                                reached = reachedWords(s, server.lastSeen, now), stale = isStale(server.lastSeen, now, nav.app.store.recentSince),
                                                takeFocus = focusOn == "recent-${server.url}",
                                                onLongClick = { if (tv) asking = server else menuFor = server },
                                                longClickLabel = if (tv) s["removeServer"] else fill(s["serverOptions"], "name" to name),
                                                actions = listOf(CustomAccessibilityAction(removeLabel) { if (tv) asking = server else remove(server); true }),
                                                trailing = if (editing) { { RemoveButton(removeLabel, { remove(server) }) } } else null,
                                                avatar = true, lineIcon = if (viaPeer) LineIcons.Globe else LineIcons.House,
                                                peerChip = if (viaPeer) s["peerChip"].orEmpty() else "",
                                            )
                                            DropdownMenu(menuFor == server, { menuFor = null }, containerColor = MaterialTheme.colorScheme.surface) {
                                                DropdownMenuItem(
                                                    text = { Text(s["removeServer"].orEmpty(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.label) },
                                                    onClick = { menuFor = null; remove(server) },
                                                    leadingIcon = { Icon(Symbols.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error) },
                                                )
                                            }
                                        }
                                    }
                                    if (tv) card() else SwipeToRemove(s["remove"].orEmpty(), { remove(server) }) { card() }
                                }
                            }
                            // A TV has Manage servers and the card's own long press for this.
                            if (!tv) {
                                DesignChips(Modifier.padding(top = LocalDesignSizes.current.gap * 0.5f)) {
                                    DesignChip(s[if (editing) "editServersDone" else "editServers"].orEmpty(), { editing = !editing }, on = editing, focusKey = "edit-servers")
                                }
                            }
                        }
                    }
                }
                if (savedFirst) { savedBlock(); foundBlock() } else { foundBlock(); savedBlock() }
            }
            // Connecting from anywhere, peer to peer, made obvious: Design 2's panel with its picture of the connection
            // and the ways in as real buttons (apple/App/ConnectParts.swift, ConnectAnywherePanel). Always shown: a copy
            // without the peer-to-peer library says so when Join is chosen.
            ConnectAnywherePanel(s) {
                WittyButton(
                    s["anywhereJoinLink"].orEmpty(), { if (nav.app.peers.available) nav.push(Route.JoinAway) else problem = s["errAwayMissing"].orEmpty() },
                    Modifier.fillMaxWidth(), kind = ButtonKind.Primary, icon = Symbols.Address, focusKey = "join-away", takeFocus = focusOn == "join-away",
                )
                if (canScan) {
                    WittyButton(
                        s["remoteScanCard"].orEmpty(), { problem = ""; scan = if (cameraAllowed(context)) ConnectScan.On else ConnectScan.Why },
                        Modifier.fillMaxWidth(), icon = Symbols.Qr, focusKey = "scan-code",
                    )
                }
                WittyButton(
                    s["enterAddress"].orEmpty(), { showForm = true; problem = "" }, Modifier.fillMaxWidth(), icon = Symbols.Address,
                    requestFocus = firstKey == "enter-address", takeFocus = focusOn == "enter-address", focusKey = "enter-address",
                )
            }
            // Where every remembered server can be removed: one, all, or those not reached for a while.
            if (recent.isNotEmpty()) {
                DesignSection(s["thisDevice"].orEmpty()) {
                    DesignRow(
                        s["manageServers"].orEmpty(), onClick = { nav.push(Route.You(YouNative.Servers)) }, focusKey = "manage-servers",
                        leading = { Icon(Symbols.Server, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(metrics.u(if (tv) 32 else 22))) },
                    )
                    // The order of this list, as Manage servers has it: what this device has used first, or what's found.
                    DesignSwitchRow(
                        s["savedServersFirst"].orEmpty(), savedFirst, { savedFirst = it; nav.app.store.savedFirst = it },
                        sub = s["savedServersFirstHint"].orEmpty(),
                    )
                }
            }
        }
        if (!tv) {
            UndoRemoval(nav, s, Modifier.align(Alignment.BottomCenter).safeDrawingPadding().padding(metrics.u(16))) { recent = nav.app.store.recent }
        }
    }
    asking?.let { server ->
        ConfirmRemove(s, server, inUse = false, onYes = { asking = null; remove(server) }, onNo = { asking = null })
    }
}

// The app's own name, the eyebrow of the screens before a server is chosen: the words its lockup had.
private const val APP_NAME = "WittyMediaClient"

// Where a found server is: its host and port, which is all it's called until it's added.
fun hostAndPort(url: String): String {
    val parsed = url.toHttpUrlOrNull() ?: return url
    val usual = (parsed.scheme == "http" && parsed.port == 80) || (parsed.scheme == "https" && parsed.port == 443)
    return if (usual) parsed.host else "${parsed.host}:${parsed.port}"
}

// A sign-in screen as a Design 2 page: with Back (the arrow on a phone, the system's and a remote's Back) where
// there's somewhere to go back to, without it where there isn't.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SignInDesign(
    onBack: (() -> Unit)?,
    title: String,
    eyebrow: String = "",
    lead: String = "",
    foot: String = "",
    top: (@Composable () -> Unit)? = null,
    actions: (@Composable FlowRowScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    if (onBack != null) {
        DesignScreen(title, onBack, eyebrow = eyebrow, lead = lead, foot = foot, actions = actions, top = top, content = content)
    } else {
        DesignPage(title, eyebrow = eyebrow, lead = lead, foot = foot, actions = actions, top = top, content = content)
    }
}

// This server as itself at the top of the screens that sign in to it: its logo and its name, coloured as the
// server colours it.
@Composable
private fun ServerLockup(nav: Nav) = Lockup(nav.brandName, nav.brandLogo)

// A big code to read across a room or type elsewhere, in the page's panel, read aloud as its digits.
@Composable
private fun BigCode(code: String, shown: String = code) {
    val ds = LocalDesignSizes.current
    val metrics = LocalMetrics.current
    Text(
        shown, color = MaterialTheme.colorScheme.onSurface,
        style = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = ds.title * 1.15f, letterSpacing = 0.2.em),
        modifier = Modifier
            .clip(metrics.corner(10))
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = ds.gap * 2.4f, vertical = ds.gap * 1.2f)
            .semantics { contentDescription = code.toList().joinToString(" ") },
    )
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
    DesignScreen(
        s["addressTitle"].orEmpty(), onBack, eyebrow = APP_NAME, lead = s["addressHint"].orEmpty(), foot = s["legalConnect"].orEmpty(), tag = "address",
        actions = { WittyButton(s["connect"].orEmpty(), onSubmit, kind = ButtonKind.Primary, busy = busy, tall = true) },
    ) {
        DesignSection("") {
            WittyField(
                address, onChange, s["addressLabel"].orEmpty(), kind = FieldKind.Address, icon = Symbols.Address,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = field,
            )
            DesignNote(problem, error = true)
        }
    }
}

// 3. Another machine is answering for a server we know. Only the person can decide, so the safe choice
// has focus, and nothing has been sent to it. No lockup: the name and logo would be that machine's.
@Composable
fun MismatchScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
    var problem by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    // The server this device remembers here, which this one isn't: after a reinstall, that's the one to remove.
    val oldOne = remember(server) { oldEntryFor(server, nav.app.store.recent) }
    DesignScreen(
        s["identityTitle"].orEmpty(), nav::pop, eyebrow = hostAndPort(server.url), lead = s["identityHint"].orEmpty(), tag = "mismatch",
        actions = {
            WittyButton(s["back"].orEmpty(), nav::pop, kind = ButtonKind.Primary, tall = true, requestFocus = true)
            if (oldOne != null) {
                WittyButton(
                    s["removeOldOne"].orEmpty(),
                    {
                        // Nothing is trusted by this: the old entry goes, and this one is met as any new server is.
                        nav.forgetServer(oldOne, undoable = false)
                        nav.pickerNotice = s["removedOldOne"].orEmpty()
                        nav.reset(Route.Connect())
                    },
                    kind = ButtonKind.Secondary, tall = true, focusKey = "remove-old-one",
                )
            }
            WittyButton(
                s["identityTrust"].orEmpty(),
                {
                    busy = true
                    scope.launch {
                        problem = nav.trust(server).orEmpty()
                        busy = false
                    }
                },
                kind = ButtonKind.Destructive, busy = busy, tall = true,
            )
        },
    ) {
        DesignSection(s["fingerprintLabel"].orEmpty()) {
            DesignRow(server.url, sub = server.fingerprint)
        }
        if (oldOne != null) DesignNote(s["reinstalledHint"].orEmpty(), Modifier.padding(top = LocalDesignSizes.current.gap), tone = true)
        DesignNote(problem, Modifier.padding(top = LocalDesignSizes.current.gap), error = true)
    }
}

// The number pad no wider than reads as a pad: on a TV it would otherwise fill the page.
@Composable
private fun padWidth(): Modifier = Modifier.widthIn(max = LocalMetrics.current.u(if (LocalMetrics.current.tv) 600 else 400)).fillMaxWidth()

// 7. A new server is opened with a six-digit code from someone already signed in. See
// docs/CLIENT-API.md, "The code is typed on the device". The pad is on screen, as a remote has no
// keyboard; number keys type too.
@Composable
fun CodeScreen(nav: Nav, s: Map<String, String>, server: SavedServer) {
    val scope = rememberCoroutineScope()
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

    // Several servers can look alike in the list: the eyebrow says which one the code goes to, and the foot its
    // fingerprint.
    val fingerprint = if (server.fingerprint.isEmpty()) "" else "${s["fingerprintLabel"]}: ${server.fingerprint}"
    Box(Modifier.digitKeys(::press, ::erase)) {
        DesignScreen(
            s["codeTitle"].orEmpty(), nav::pop, eyebrow = server.name.ifEmpty { "WittyMediaServer" }, lead = s["codeHint"].orEmpty(), foot = fingerprint, tag = "code",
            actions = {
                WittyButton(s["usePassword"].orEmpty(), { nav.signInTo(server, SignInWay.Password) }, kind = ButtonKind.Secondary)
                WittyButton(s["showCodeInstead"].orEmpty(), { nav.signInTo(server, SignInWay.ShownCode) }, kind = ButtonKind.Secondary)
            },
        ) {
            DesignSection("") {
                CodeBoxes(entry.digits, entry.busy, wrong)
                // Only there while there's something to say, as on Apple TV.
                if (entry.busy) DesignNote(s["connecting"].orEmpty(), busy = true) else DesignNote(problem, error = true)
            }
            DesignSection("") {
                NumberPad(::press, ::erase, padWidth(), firstFocus = true)
            }
        }
    }
}

// 8. The TV shows a code; someone already signed in on a phone or computer approves it, so nobody
// has to type a password with a remote. See docs/CLIENT-API.md.
@Composable
private fun PairScreen(nav: Nav, s: Map<String, String>, onBack: () -> Unit, onUsePassword: () -> Unit) {
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
    DesignScreen(
        s["pairTitle"].orEmpty(), onBack, lead = if (code.isNotEmpty()) s["pairHint"].orEmpty() else "", tag = "pair",
        top = { ServerLockup(nav) },
        actions = {
            if (ended) {
                if (limited) WittyButton(s["usePassword"].orEmpty(), onUsePassword, kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-password")
                else WittyButton(s["pairNew"].orEmpty(), { round++ }, kind = ButtonKind.Primary, tall = true, takeFocus = true, focusKey = "pair-new")
            }
            val server = nav.server
            if (server != null && server.publicKey.isNotEmpty()) {
                WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Secondary, focusKey = "typed-code")
            }
            if (!limited) WittyButton(s["usePassword"].orEmpty(), onUsePassword, kind = ButtonKind.Secondary, requestFocus = code.isNotEmpty(), focusKey = "use-password")
            WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Secondary, focusKey = "change-server")
        },
    ) {
        val ds = LocalDesignSizes.current
        DesignSection("") {
            if (code.isNotEmpty()) {
                SelectionContainer {
                    Text(approveAt, color = LocalExtraColours.current.accentText, fontSize = ds.body, fontWeight = FontWeight.Bold)
                }
                BigCode(code)
                DesignNote(if (waiting) s["errLost"].orEmpty() else s["pairWaiting"].orEmpty(), busy = true)
            } else if (!ended) {
                Spinner(MaterialTheme.colorScheme.onSurfaceVariant, LocalMetrics.current.u(if (LocalMetrics.current.tv) 40 else 24))
            }
            DesignNote(problem, error = true)
        }
        if (code.isNotEmpty() && scan.isNotEmpty()) {
            DesignSection("") { QrCard(scan, s["pairScan"].orEmpty()) }
        }
    }
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
            // With a QR code and a PIN where the server has them; the code alone on an older one.
            step == Step.Pair -> PairWithQr(nav, s, onBack = { back(pairFrom ?: Step.Usual) }, onUsePassword = { back(pairFrom ?: Step.Usual) }) {
                PairScreen(nav, s, onBack = { back(pairFrom ?: Step.Usual) }) { back(pairFrom ?: Step.Usual) }
            }
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
                    nav.app.getSharedPreferences("wms.signin", android.content.Context.MODE_PRIVATE).edit().putLong(lastProfileKey(nav), p.id).apply()
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

// The quiet ways to sign in without a password here, as the page's other actions, then another server.
@Composable
private fun CodeLinks(nav: Nav, s: Map<String, String>, onUseCode: () -> Unit, otherAccount: (() -> Unit)? = null) {
    if (otherAccount != null) WittyButton(s["otherAccount"].orEmpty(), otherAccount, kind = ButtonKind.Secondary, focusKey = "other-account")
    WittyButton(s["useCode"].orEmpty(), onUseCode, kind = ButtonKind.Secondary, focusKey = "use-code")
    // Only a server that has proved its identity can be sent a code.
    val server = nav.server
    if (server != null && server.publicKey.isNotEmpty()) {
        WittyButton(s["codeTitle"].orEmpty(), { nav.push(Route.Code(server)) }, kind = ButtonKind.Secondary, focusKey = "typed-code")
    }
    WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Quiet, focusKey = "change-server")
}

// The profile this device last chose on this server, so the remote starts on it.
private fun lastProfileKey(nav: Nav): String = "last." + (nav.server?.serverId?.ifEmpty { null } ?: nav.app.api.base)

// 4. Who's watching? Profiles as faces, as many across as fit, under this server's lockup.
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
    // A TV with many people draws smaller faces so two centred rows and the buttons below them still fit.
    val size = metrics.u(
        when {
            metrics.tv -> if (profiles.size > 4) 150 else 200
            metrics.tablet -> 140
            else -> 104
        },
    )
    val last = remember { nav.app.getSharedPreferences("wms.signin", android.content.Context.MODE_PRIVATE).getLong(lastProfileKey(nav), -1L) }
    if (metrics.tv) {
        // The TV's picker is the web's: one centred column (TvWhoPage).
        TvWhoPage(
            s["whoTitle"].orEmpty(),
            top = { ServerLockup(nav) },
            problem = { DesignNote(problem, error = true) },
            profiles = {
                FlowRow(
                    Modifier.fillMaxWidth().remoteRow(),
                    horizontalArrangement = Arrangement.spacedBy(metrics.u(48), Alignment.CenterHorizontally),
                    verticalArrangement = Arrangement.spacedBy(metrics.u(28)),
                ) {
                    profiles.forEachIndexed { i, p ->
                        key(p.id) { ProfileTile(p, size, { if (!busy) onPick(p) }, requestFocus = if (last in profiles.map { it.id }) p.id == last else i == 0, focusKey = "profile-${p.id}") }
                    }
                }
            },
            actions = {
                WittyButton(s["otherAccount"].orEmpty(), onOtherAccount, kind = ButtonKind.Secondary, focusKey = "other-account", modifier = Modifier.fillMaxWidth())
                WittyButton(s["usePhone"] ?: s["useCode"].orEmpty(), onUseCode, kind = ButtonKind.Secondary, focusKey = "use-code", modifier = Modifier.fillMaxWidth())
            },
            foot = { WittyButton(s["changeServer"].orEmpty(), nav::changeServer, kind = ButtonKind.Quiet, focusKey = "change-server") },
        )
        return
    }
    DesignPage(
        s["whoTitle"].orEmpty(), tag = "who", top = { ServerLockup(nav) },
        actions = { CodeLinks(nav, s, onUseCode, onOtherAccount) },
    ) {
        DesignSection("") {
            // Wrapping rather than scrolling, so nothing clips a lifted, ringed avatar.
            FlowRow(
                Modifier.fillMaxWidth().remoteRow().padding(vertical = metrics.u(8)),
                horizontalArrangement = Arrangement.spacedBy(metrics.u(if (metrics.tv) 48 else 24)),
                verticalArrangement = Arrangement.spacedBy(metrics.u(28)),
                maxItemsInEachRow = if (metrics.tv || metrics.tablet) Int.MAX_VALUE else 2,
            ) {
                profiles.forEachIndexed { i, p ->
                    key(p.id) { ProfileTile(p, size, { if (!busy) onPick(p) }, requestFocus = i == 0, focusKey = "profile-${p.id}") }
                }
            }
            DesignNote(problem, error = true)
        }
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
    val shown = avatarName(who.displayName, who.name)
    // The face, then its name as the title, and the username over it where the name isn't it.
    DesignScreen(
        shown, onBack, eyebrow = if (showsUsername(who.displayName, who.name)) "@${who.name}" else "", lead = s["passwordHint"].orEmpty(), tag = "password",
        top = { ProfileFace(shown, who.avatar, metrics.u(if (metrics.tv) 160 else 96)) },
        actions = {
            WittyButton(s["signIn"].orEmpty(), onSubmit, kind = ButtonKind.Primary, busy = busy, tall = true)
            ForgotPassword(nav, s)
        },
    ) {
        DesignSection("") {
            WittyField(
                password, onChange, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = field, isError = refused, shake = wrongPasswords,
            )
            DesignNote(problem, error = true)
        }
    }
}

// docs/APP-DESIGN.md, Avatar 5: wherever a face shows with its names, they're centred under it.
@Composable
fun FaceWithNames(who: Profile, size: androidx.compose.ui.unit.Dp, modifier: Modifier = Modifier) {
    val metrics = LocalMetrics.current
    val shown = avatarName(who.displayName, who.name)
    Column(modifier.width(IntrinsicSize.Max).widthIn(min = size), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(metrics.u(8))) {
        ProfileFace(shown, who.avatar, size, Modifier.padding(bottom = metrics.u(if (metrics.tv) 8 else 0)))
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
    SignInDesign(
        onBack, s["signInTitle"].orEmpty(), top = { ServerLockup(nav) },
        actions = {
            WittyButton(s["signIn"].orEmpty(), onSubmit, kind = ButtonKind.Primary, busy = busy, tall = true, requestFocus = metrics.tv, focusKey = "sign-in")
            CodeLinks(nav, s, onUseCode)
        },
    ) {
        DesignSection("") {
            WittyField(
                name, onName, s["usernameLabel"].orEmpty(), kind = FieldKind.Username, icon = Symbols.Person,
                imeAction = ImeAction.Next, onAction = { runCatching { second.requestFocus() } }, focusRequester = first,
                isError = refused, shake = wrongPasswords,
            )
            WittyField(
                password, onPassword, s["passwordLabel"].orEmpty(), kind = FieldKind.Password, icon = Symbols.Password,
                imeAction = ImeAction.Go, onAction = onSubmit, focusRequester = second, isError = refused, shake = wrongPasswords,
            )
            DesignNote(problem, error = true)
        }
    }
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
    Box(if (useRecovery) Modifier else Modifier.digitKeys(press, erase)) {
        DesignScreen(
            s[if (useRecovery) "recoveryTitle" else "twoFactorTitle"].orEmpty(), onBack,
            lead = s[if (useRecovery) "recoveryHint" else "twoFactorHint"].orEmpty(), tag = "two-factor",
            top = {
                if (who != null) ProfileFace(avatarName(who.displayName, who.name), who.avatar, metrics.u(if (metrics.tv) 160 else 96))
                else ServerLockup(nav)
            },
            actions = {
                if (useRecovery) WittyButton(s["signIn"].orEmpty(), onSubmitRecovery, kind = ButtonKind.Primary, busy = checking, tall = true)
                WittyButton(
                    s[if (useRecovery) "useAuthenticatorCode" else "useRecoveryCode"].orEmpty(), onSwitch,
                    kind = ButtonKind.Secondary, focusKey = "recovery-switch",
                )
            },
        ) {
            DesignSection("") {
                if (useRecovery) {
                    WittyField(
                        recovery, onRecovery, s["recoveryLabel"].orEmpty(), icon = Symbols.Key, imeAction = ImeAction.Go,
                        onAction = onSubmitRecovery, focusRequester = recoveryField, isError = problem.isNotEmpty(), shake = wrong, maxLength = RECOVERY_MOST,
                    )
                } else {
                    Box {
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
                }
                DesignNote(problem, error = true)
            }
            if (!useRecovery && metrics.tv) {
                DesignSection("") { NumberPad(press, erase, padWidth(), firstFocus = true) }
            }
        }
    }
}

// The server takes at most 32 characters of a code.
private const val RECOVERY_MOST = 32

// What a TV doesn't open itself, such as the help on a forgotten password: a QR code for a phone, with
// the address under it, as Apple TV has.
@Composable
fun OnPhoneScreen(nav: Nav, s: Map<String, String>, title: String, path: String) {
    // An editor a TV doesn't open (the server's tvLevels, net/TvLevels.kt) says so in the server's words, with what
    // is set now; anything else a TV sends to a phone just says to open it there.
    val screen = remember(path, nav.tvLevels) { nav.tvLevels?.screenFor(path) }
    val note = nav.tvLevels?.note.orEmpty().takeIf { screen != null || path.startsWith("/settings/appearance") }
    var summary by remember(path) { mutableStateOf(com.wittywilla.wittymediaclient.net.TvSummary()) }
    LaunchedEffect(path) { runCatching { nav.app.api.tvSummary(screen?.summary.orEmpty()) }.onSuccess { summary = it } }
    val base = remember(path) { runCatching { nav.app.api.mediaUrl("/") }.getOrDefault("") }
    val address = if (base.isEmpty()) "" else com.wittywilla.wittymediaclient.net.tvCardAddress(base, path, summary.addresses)
    // Centred, as the sign-in screens: OnAComputer.kt. The server's own words (naming the WittyMediaClient app) at the foot.
    val editor = note != null
    OnAComputerCard(
        title = title,
        line = if (editor) s["tvCardLine"].orEmpty() else s["openOnPhone"].orEmpty().removeSuffix(":"),
        address = address,
        summary = summary.lines,
        onBack = nav::pop,
        backLabel = s["back"].orEmpty(),
        orOpen = s["tvCardOrOpen"].orEmpty(),
        footer = if (editor) listOf(note.orEmpty(), s["tvCardApplies"].orEmpty()).filter { it.isNotEmpty() }.joinToString(" ") else "",
        icon = onAComputerIcon(path),
        lockup = { ServerLockup(nav) },
    )
}

// "This server isn't set up yet": first-time setup happens in a web browser only, and the app doesn't connect (or try to
// sign in) until it is done. The address to finish it at, with a QR code of it, then Check again or another server.
@Composable
fun SetupRequiredScreen(s: Map<String, String>, address: String, retry: () -> Unit, back: () -> Unit) {
    DesignScreen(
        s["setupNeededTitle"].orEmpty(), back, eyebrow = hostAndPort(address), lead = s["setupNeededDetail"].orEmpty(), tag = "setup-needed",
        actions = {
            WittyButton(s["setupNeededRetry"].orEmpty(), retry, kind = ButtonKind.Primary, tall = true, requestFocus = true, focusKey = "setup-retry")
            WittyButton(s["back"].orEmpty(), back, kind = ButtonKind.Secondary, tall = true, focusKey = "setup-back")
        },
    ) {
        DesignSection("") {
            QrCard(address, s["pairScan"].orEmpty())
            Text(
                address, color = LocalExtraColours.current.accentText, fontSize = LocalDesignSizes.current.body, fontWeight = FontWeight.Bold,
                modifier = Modifier.semantics { contentDescription = "Finish setup in a web browser at $address" },
            )
        }
    }
}

// Where the camera is, for reading a QR code on the connect page.
private enum class ConnectScan { Off, Why, Denied, On }
